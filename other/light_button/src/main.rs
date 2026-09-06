#![no_std]
#![no_main]

mod ble;
mod config;
#[cfg(not(feature = "debug"))]
mod no_debug;
mod other;
mod peripherals;
mod prelude;

use embassy_executor::Spawner;
use nrf_mpsl::MultiprotocolServiceLayer;
use static_cell::StaticCell;

use prelude::*;

#[cfg(feature = "debug")]
use {defmt_rtt as _, panic_probe as _};

#[cfg(not(feature = "debug"))]
mod panic_handler;

bind_interrupts!(struct Irqs {
    RNG => rng::InterruptHandler<embassy_nrf::peripherals::RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    SAADC => embassy_nrf::saadc::InterruptHandler;
});

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    // ------------------------------------------------------------
    // nRF initialization
    // ------------------------------------------------------------

    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = LfclkSource::ExternalXtal;

    let p = embassy_nrf::init(config);

    info!("Nordicoin start");

    // ------------------------------------------------------------
    // MPSL
    // ------------------------------------------------------------

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

    let mpsl = MPSL.init(MultiprotocolServiceLayer::new(mpsl_p, Irqs, lfclk_cfg).unwrap());

    spawner.spawn(mpsl_task(mpsl).unwrap());

    // ------------------------------------------------------------
    // SoftDevice Controller peripherals
    // ------------------------------------------------------------

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );

    // ------------------------------------------------------------
    // RNG
    // ------------------------------------------------------------

    static RNG: StaticCell<rng::Rng<embassy_nrf::mode::Async>> = StaticCell::new();

    let rng = RNG.init(rng::Rng::new(p.RNG, Irqs));

    // ------------------------------------------------------------
    // SDC memory
    // ------------------------------------------------------------

    static SDC_MEM: StaticCell<sdc::Mem<6144>> = StaticCell::new();

    let sdc_mem = SDC_MEM.init(sdc::Mem::<6144>::new());

    // ------------------------------------------------------------
    // SoftDevice Controller
    // ------------------------------------------------------------

    let sdc = ble::build_sdc(sdc_p, rng, mpsl, sdc_mem).unwrap();

    // ------------------------------------------------------------
    // Start BLE task.
    //
    // HostResources, Stack, Runner and Central are all created
    // inside run_ble_task().
    // ------------------------------------------------------------
spawner.spawn(ble::run_ble_task(sdc).unwrap());
    spawner.spawn(
        peripherals_task(
            spawner,
            peripherals::led::LedController::new(20, p.P0_20),
            Input::new(p.P0_16, Pull::Down), // Needs a pull down! and without external resistor
        )
        .unwrap(),
    );

    LED_CHANNEL.send(LedCommand::Blink).await;
}
