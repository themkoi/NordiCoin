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
use embassy_nrf::{bind_interrupts, config::LfclkSource, rng};
use nrf_mpsl::MultiprotocolServiceLayer;
use static_cell::StaticCell;

use prelude::*;

#[cfg(feature = "debug")]
use defmt_rtt as _;
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

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = LfclkSource::ExternalXtal; // Decreases power consumption by 0.5 uA
    let p = embassy_nrf::init(config);

    info!("Nordicoin start");

    // LED
    spawner.spawn(led_task(peripherals::led::LedController::new(20, p.P0_20)).unwrap());
    LED_CHANNEL.send(LedCommand::Blink).await; // At init

    // Flash
    static FLASH: StaticCell<peripherals::flash::FlashStorage> = StaticCell::new();
    let flash: &'static mut peripherals::flash::FlashStorage =
        FLASH.init(peripherals::flash::FlashStorage::new(p.NVMC).await);

    // ADC
    let adc_reader = AdcReader::new(p.SAADC, Irqs).await;

    // BLE
    let mpsl_p: nrf_mpsl::Peripherals<'_> =
        mpsl::Peripherals::new(p.RTC0, p.TIMER0, p.TEMP, p.PPI_CH19, p.PPI_CH30, p.PPI_CH31);
    let lfclk_cfg = mpsl::raw::mpsl_clock_lfclk_cfg_t {
        source: mpsl::raw::MPSL_CLOCK_LF_SRC_RC as u8,
        rc_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_CTIV as u8,
        rc_temp_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_TEMP_CTIV as u8,
        accuracy_ppm: mpsl::raw::MPSL_DEFAULT_CLOCK_ACCURACY_PPM as u16,
        skip_wait_lfclk_started: mpsl::raw::MPSL_DEFAULT_SKIP_WAIT_LFCLK_STARTED != 0,
    };
    static MPSL: StaticCell<MultiprotocolServiceLayer> = StaticCell::new();
    let mpsl: &mut MultiprotocolServiceLayer<'static> =
        MPSL.init(mpsl::MultiprotocolServiceLayer::new(mpsl_p, Irqs, lfclk_cfg).unwrap());
    spawner.spawn(mpsl_task(mpsl).unwrap());

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    static RNG: StaticCell<rng::Rng<embassy_nrf::mode::Async>> = StaticCell::new();
    let rng: &mut rng::Rng<embassy_nrf::mode::Async> = RNG.init(rng::Rng::new(p.RNG, Irqs));

    static SDC_MEM: StaticCell<sdc::Mem<SDC_MEM_SIZE>> = StaticCell::new();
    let sdc_mem: &mut sdc::Mem<SDC_MEM_SIZE> = SDC_MEM.init(sdc::Mem::new());
    let sdc: SoftdeviceController<'static> = build_sdc(sdc_p, rng, mpsl, sdc_mem).unwrap();
    spawner.spawn(ble_task(sdc, adc_reader, flash).unwrap());

    // PWM
    spawner.spawn(
        pwm_task(peripherals::pwm::PwmController::new(
            p.TIMER1,
            p.PPI_CH0,
            p.PPI_CH1,
            p.GPIOTE_CH0,
            p.P0_18.into(),
        ))
        .unwrap(),
    );
}
