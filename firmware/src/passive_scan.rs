#![no_std]
#![no_main]

use core::cell::RefCell;

use defmt::info;
use defmt::unwrap;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::RNG;
use embassy_nrf::{bind_interrupts, rng};
use embassy_time::{Duration, Timer};
use heapless::Deque;
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use static_cell::StaticCell;
use trouble_host::prelude::*;
use {defmt_rtt as _, panic_probe as _};

/// Maximum number of connections (unused in scanner-only mode, but required by host)
const CONNECTIONS_MAX: usize = 1;
/// Maximum L2CAP channels
const L2CAP_CHANNELS_MAX: usize = 1;

// ─── Interrupt bindings ───────────────────────────────────────────────
// These are required by nrf-sdc's MPSL for radio scheduling.
bind_interrupts!(struct Irqs {
    RNG => rng::InterruptHandler<RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
});

// ─── MPSL background task ─────────────────────────────────────────────
/// Runs the Multi-Protocol Service Layer in the background.
/// This handles radio scheduling between BLE and other protocols via PPI.
#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

// ─── SDC builder ──────────────────────────────────────────────────────
/// Configure and build the Softdevice Controller with scan + central support.
fn build_sdc<'d, const N: usize>(
    p: nrf_sdc::Peripherals<'d>,
    rng: &'d mut rng::Rng<Async>,
    mpsl: &'d MultiprotocolServiceLayer,
    mem: &'d mut sdc::Mem<N>,
) -> Result<nrf_sdc::SoftdeviceController<'d>, nrf_sdc::Error> {
    sdc::Builder::new()?
        .support_scan()
        .support_ext_scan()
        .support_central()
        .support_ext_central()
        .central_count(1)?
        .build(p, rng, mpsl, mem)
}

// ─── Advertisement report printer ─────────────────────────────────────
/// Tracks and prints unique BLE device addresses seen during scanning.
struct Printer {}

impl EventHandler for Printer {
    fn on_adv_reports(&self, mut it: LeAdvReportsIter<'_>) {
        while let Some(Ok(report)) = it.next() {
            // Only print each device once
            info!(
                "PASSIVE SCAN: discovered {:?} ({:?})",
                report.addr, report.data
            );
        }
    }
}

// ─── Main entry point ─────────────────────────────────────────────────
#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    // config.dcdc.reg1 = true; // Broken when radio is on
    let p = embassy_nrf::init(config);

    info!("Nordicoin Passive BLE Scanner starting!");

    // ── Step 1: Initialize MPSL (Multi-Protocol Service Layer) ─────────
    // MPSL time-slices the RADIO peripheral between BLE and other protocols.
    // It uses PPI to wake from System ON idle → RADIO events without CPU.
    let mpsl_p =
        mpsl::Peripherals::new(p.RTC0, p.TIMER0, p.TEMP, p.PPI_CH19, p.PPI_CH30, p.PPI_CH31);
    let lfclk_cfg = mpsl::raw::mpsl_clock_lfclk_cfg_t {
        source: mpsl::raw::MPSL_CLOCK_LF_SRC_RC as u8,
        rc_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_CTIV as u8,
        rc_temp_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_TEMP_CTIV as u8,
        accuracy_ppm: mpsl::raw::MPSL_DEFAULT_CLOCK_ACCURACY_PPM as u16,
        skip_wait_lfclk_started: mpsl::raw::MPSL_DEFAULT_SKIP_WAIT_LFCLK_STARTED != 0,
    };
    static MPSL: StaticCell<MultiprotocolServiceLayer> = StaticCell::new();
    let mpsl = MPSL.init(unwrap!(mpsl::MultiprotocolServiceLayer::new(
        mpsl_p, Irqs, lfclk_cfg
    )));
    spawner.spawn(unwrap!(mpsl_task(&*mpsl)));

    // ── Step 2: Initialize the Softdevice Controller (SDC) ─────────────
    // The SDC sits between the HCI layer and the radio. It handles
    // BLE protocol state machines, link management, etc.
    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    let mut rng = rng::Rng::new(p.RNG, Irqs);

    // ~3 KB heap for SDC — enough for scan + 1 central connection
    let mut sdc_mem = sdc::Mem::<3224>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    // Brief delay to let radio stabilize
    Timer::after(Duration::from_millis(200)).await;

    // ── Step 3: Initialize the Trouble BLE Host stack ──────────────────
    // The host manages GATT, scanning, connections, etc. on top of HCI.
    let address: Address = Address::random([0xff, 0x8f, 0x1b, 0x05, 0xe4, 0xff]);

    let mut resources: HostResources<_, DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();
    let mut central = stack.central();
    let mut runner = stack.runner();

    // ── Step 4: Set up passive scan config ─────────────────────────────
    // KEY PASSIVE SCANNING PARAMETERS:
    //   active = false  →  never transmit scan requests (passive only)
    //   phys = M1       →  1 Mbps PHY (best range, lowest current)
    //   interval = 10s  →  scan window every 10 seconds (ultra low duty cycle)
    //   window = 30ms   →  radio active for only 30ms per cycle
    //   timeout = 0     →  scan forever (no timeout)
    let mut config = ScanConfig::default();
    config.active = false; // ← PASSIVE: no scan request TX
    config.phys = PhySet::M1; // 1 Mbps PHY (lowest power)
    config.interval = Duration::from_secs(3); // Wide interval = low duty cycle
    config.window = Duration::from_millis(75); // Short active window
    config.timeout = Duration::from_secs(0); // 0 = scan forever

    info!(
        "Starting passive scan (interval={}ms, window={}ms)",
        config.interval.as_millis(),
        config.window.as_millis()
    );

    // ── Step 5: Run scanner + host event loop concurrently ─────────────
    let printer = Printer {};
    let mut scanner = Scanner::new(&mut central);

    let _ = join(
        // Run the host event loop (handles HCI events, GATT, etc.)
        runner.run_with_handler(&printer),
        // Run the scanner loop
        scanner.scan(&config),
    )
    .await;
}
