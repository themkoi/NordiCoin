#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::saadc::{
    self, ChannelConfig, Config as SaadcConfig, Oversample, Saadc, VddInput,
};
use embassy_nrf::peripherals::SAADC;
use embassy_nrf::bind_interrupts;
use embassy_sync::blocking_mutex::raw::NoopRawMutex;
use embassy_sync::mutex::Mutex;
use embassy_time::{Duration, Timer};
use static_cell::StaticCell;
use {defmt_rtt as _, panic_probe as _};

pub struct VddReader {
    saadc: &'static Mutex<NoopRawMutex, Saadc<'static, 1>>,
    divider_ratio: f32,
}

impl VddReader {
    pub fn new(
        saadc: embassy_nrf::Peri<'_, SAADC>,
        irq: impl embassy_nrf::interrupt::typelevel::Binding<
            embassy_nrf::interrupt::typelevel::SAADC,
            saadc::InterruptHandler,
        > + 'static,
        divider_ratio: f32,
    ) -> &'static Self {
        let saadc: embassy_nrf::Peri<'static, SAADC> = unsafe {
            core::mem::transmute(saadc)
        };

        let channel_config = ChannelConfig::single_ended(VddInput);

        let mut config = SaadcConfig::default();
        config.oversample = Oversample::Over64x;

        static SAADC_MUTEX: StaticCell<Mutex<NoopRawMutex, Saadc<'static, 1>>> =
            StaticCell::new();
        let mutex = SAADC_MUTEX.init(Mutex::new(Saadc::new(
            saadc,
            irq,
            config,
            [channel_config],
        )));

        static READER: StaticCell<VddReader> = StaticCell::new();
        READER.init(VddReader {
            saadc: mutex,
            divider_ratio,
        })
    }

    pub async fn read_vdd_mv(&self) -> u16 {
        let sample1 = self.sample_once().await;
        let sample2 = self.sample_once().await;
        let avg = (sample1 + sample2) / 2;

        let vdd_mv = (avg as u32 * 600 * self.divider_ratio as u32) / 65536;

        vdd_mv as u16
    }

    async fn sample_once(&self) -> i16 {
        let mut buf = [0i16; 1];
        let mut saadc = self.saadc.lock().await;
        saadc.sample(&mut buf).await;
        buf[0]
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

    let vdd_reader = VddReader::new(p.SAADC, Irqs, 2.0);

    loop {
        let vdd_mv = vdd_reader.read_vdd_mv().await;
        info!("VDD = {} mV", vdd_mv);
        Timer::after(Duration::from_secs(1)).await;
    }
}
