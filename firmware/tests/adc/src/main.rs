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

pub struct AdcReader {
    saadc: &'static Mutex<NoopRawMutex, Saadc<'static, 1>>,
}

impl AdcReader {
    pub async fn new(
        saadc: embassy_nrf::Peri<'_, SAADC>,
        irq: impl embassy_nrf::interrupt::typelevel::Binding<
            embassy_nrf::interrupt::typelevel::SAADC,
            saadc::InterruptHandler,
        > + 'static,
    ) -> &'static Self {
        let saadc: embassy_nrf::Peri<'static, SAADC> = unsafe {
            core::mem::transmute(saadc)
        };

        let mut channel_config = ChannelConfig::single_ended(VddInput);
        channel_config.gain = saadc::Gain::Gain1_6;

        let mut config = SaadcConfig::default();
        config.oversample = Oversample::Over256x;
        config.resolution = saadc::Resolution::_14bit;
        let saadc_real = Saadc::new(
            saadc,
            irq,
            config,
            [channel_config],
        );
        saadc_real.calibrate().await;

        static SAADC_MUTEX: StaticCell<Mutex<NoopRawMutex, Saadc<'static, 1>>> =
            StaticCell::new();
        let mutex = SAADC_MUTEX.init(Mutex::new(saadc_real));

        static READER: StaticCell<AdcReader> = StaticCell::new();
        READER.init(AdcReader {
            saadc: mutex,
        })
    }

    /// Convert raw SAADC sample to voltage in millivolts.
    ///
    /// SAADC formula: result = V_in * GAIN / REFERENCE * 2^RESOLUTION
    ///
    /// With: Gain = 1/6, Reference = 0.6V (internal), Resolution = 14-bit (2^14 = 16384)
    ///
    /// V_in = result * REFERENCE / (GAIN * 2^RESOLUTION)
    ///      = result * 0.6 / (1/6 * 16384)
    ///      = result * 3.6 / 16384
    ///
    /// In millivolts: V_mV = result * 3600 / 16384 = result * 225 / 1024
    ///
    /// Using integer arithmetic: (result * 225) >> 10
    ///
    /// For VDD measurement: result is always >= 0.
    pub fn raw_to_mv(raw: i16) -> i32 {
        (raw as i32 * 225) >> 10
    }

    pub async fn read_raw(&self) -> i16 {
        self.sample_once().await
    }

    pub async fn read_mv(&self) -> i32 {
        let raw = self.sample_once().await;
        Self::raw_to_mv(raw)
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

    let adc_reader = AdcReader::new(p.SAADC, Irqs).await;

    loop {
        let mv = adc_reader.read_mv().await;
        info!("ADC VDD = {} mV", mv);
        Timer::after(Duration::from_secs(1)).await;
    }
}
