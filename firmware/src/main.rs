#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    // config.hfclk_source = embassy_nrf::config::HfclkSource::ExternalXtal; // Don't, we don't have the 30Mhz Xtal
    // config.dcdc.reg1 = true; // Try this later for radio optimisations
    let p = embassy_nrf::init(config);
    
    info!("Starting");

    loop {
        info!("Tick");
        Timer::after(Duration::from_secs(3)).await;
    }
}
