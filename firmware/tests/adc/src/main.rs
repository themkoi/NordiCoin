/*
 * SAADC VDD measurement
 * =====================
 * Gain = 1/6, Reference = 0.6V (internal), Resolution = 14-bit (2^14 = 16384)
 *   result = V_in * GAIN / REFERENCE * 2^RESOLUTION
 *   V_in  = result * REFERENCE / (GAIN * 2^RESOLUTION)
 *         = result * 0.6 / (1/6 * 16384)
 *         = result * 3.6 / 16384
 * In mV: V_mV = result * 3600 / 16384 = result * 225 / 1024
 * Integer: (result * 225) >> 10
 */

#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::saadc::{
    self, ChannelConfig, Config as SaadcConfig, Oversample, Saadc, VddInput,
};
use embassy_nrf::bind_interrupts;
use embassy_nrf::peripherals::SAADC;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

pub struct AdcReader {
    saadc: Saadc<'static, 1>,
}

impl AdcReader {
    pub async fn new(
        saadc: embassy_nrf::Peri<'static, SAADC>,
        irq: impl embassy_nrf::interrupt::typelevel::Binding<
            embassy_nrf::interrupt::typelevel::SAADC,
            saadc::InterruptHandler,
        > + 'static,
    ) -> Self {
        let mut channel_config = ChannelConfig::single_ended(VddInput);
        channel_config.gain = saadc::Gain::Gain1_6;
        let mut config = SaadcConfig::default();
        config.oversample = Oversample::Over256x;
        config.resolution = saadc::Resolution::_14bit;
        let saadc = Saadc::new(saadc, irq, config, [channel_config]);
        saadc.calibrate().await;

        AdcReader {saadc}
    }

    pub async fn get_mv(&mut self) -> i32 {
        let mut buf = [0i16; 1];
        self.saadc.sample(&mut buf).await;
        (buf[0] as i32 * 225) >> 10
    }
}

bind_interrupts!(struct Irqs {
    SAADC => embassy_nrf::saadc::InterruptHandler;
});

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    let mut adc_reader = AdcReader::new(p.SAADC, Irqs).await;

    loop {
        let mv = adc_reader.get_mv().await;
        info!("ADC VDD = {} mV", mv);
        Timer::after(Duration::from_secs(1)).await;
    }
}
