#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::config::LfclkSource;
use {defmt_rtt as _, panic_probe as _};

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = LfclkSource::ExternalXtal; // Decreases power consumption by 0.5 uA
    let _p = embassy_nrf::init(config);

    info!("Empty nRF project running!");
}
