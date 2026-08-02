use embassy_nrf::{peripherals::SAADC, saadc::{self, ChannelConfig, Oversample, Saadc, VddInput, Config as SaadcConfig}};
use crate::prelude::*;

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
        config.oversample = Oversample::Over16x;
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

    pub async fn get_bat_byte(&mut self) -> u8 {
        let mv = self.get_mv().await;
        info!("Battery mv is: {:?}", mv);
        let bat = if mv < 1800 {
            0
        } else if mv >= 3300 {
            255
        } else {
            ((mv - 1800) * 255 / 1500) as u8
        };
        info!("Battery byte is: {}", bat);
        bat
    }
}
