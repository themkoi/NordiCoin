#![no_std]
#![no_main]

use defmt::info;
use defmt::unwrap;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::RNG;
use embassy_nrf::{bind_interrupts, rng};
use embassy_time::{Duration, Timer};
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use static_cell::StaticCell;
use bt_hci::param::FilterDuplicates;
use trouble_host::prelude::*;
use {defmt_rtt as _, panic_probe as _};

const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 1;

bind_interrupts!(struct Irqs {
    RNG => rng::InterruptHandler<RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
});

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

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

/// Scan interval: how often we wake up to listen (in ms).
/// Shorter = more power but faster discovery.
const SCAN_INTERVAL_MS: u64 = 3000;

/// Scan window: how long the radio is ON during each cycle (in ms).
/// Smaller = more power efficient but may miss packets.
const SCAN_WINDOW_MS: u64 = 40;

/// Sleep duration between scan cycles (in ms).
/// Longer sleep = more power efficient.
const SLEEP_BETWEEN_SCANS_MS: u64 = 3000;

struct SeenDevices;

impl SeenDevices {
    const fn new() -> Self {
        Self
    }
}

impl EventHandler for SeenDevices {
    fn on_adv_reports(&self, mut it: LeAdvReportsIter<'_>) {
        while let Some(Ok(report)) = it.next() {
            info!(
                "PASSIVE SCAN: discovered {:?} ({:?})",
                report.addr, report.data
            );
        }
    }
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    info!("Nordicoin Passive BLE Scanner starting (low-power duty-cycled)!");

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

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    let mut rng = rng::Rng::new(p.RNG, Irqs);

    // SDC memory: scan + central support, 1 connection slot
    let mut sdc_mem = sdc::Mem::<3224>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    Timer::after(Duration::from_millis(200)).await;

    let address: Address = Address::random([0xff, 0x8f, 0x1b, 0x05, 0xe4, 0xff]);

    let mut resources: HostResources<_, DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();
    let central = stack.central();
    let mut runner = stack.runner();

    let mut scan_config = ScanConfig::default();
    scan_config.active = false;
    scan_config.phys = PhySet::M1;
    scan_config.interval = Duration::from_millis(SCAN_INTERVAL_MS);
    scan_config.window = Duration::from_millis(SCAN_WINDOW_MS);
    scan_config.timeout = Duration::from_secs(0);
    scan_config.filter_duplicates = FilterDuplicates::Enabled;

    info!(
        "Starting low-power passive scan (interval={}ms, window={}ms, sleep={}ms)",
        SCAN_INTERVAL_MS, SCAN_WINDOW_MS, SLEEP_BETWEEN_SCANS_MS
    );

    let seen = SeenDevices::new();
    let mut scanner = Scanner::new(central);

    let _ = join(
        runner.run_with_handler(&seen),
        async {
            loop {
                match scanner.scan(&scan_config).await {
                    Ok(_session) => {
                        Timer::after(Duration::from_millis(SLEEP_BETWEEN_SCANS_MS)).await;
                    }
                    Err(e) => {
                        defmt::error!("Scan error: {:?}", e);
                        Timer::after(Duration::from_millis(SLEEP_BETWEEN_SCANS_MS)).await;
                    }
                }
            }
        },
    )
    .await;
}
