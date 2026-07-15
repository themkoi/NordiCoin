#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Input, Pull};
use embassy_time::Timer;
use {defmt_rtt as _, panic_probe as _};

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    info!("Button test on P0.16");
    info!("Waiting for button press");

    Timer::after_secs(20).await;

    let mut button = Input::new(p.P0_16, Pull::Down); // Needs a pull down! and without external resistor

    // Even tho it's interrupt, it's highly inneficient

    loop {
        button.wait_for_low().await;
        info!("Button pressed!");
        button.wait_for_high().await;
        info!("Button released");
    }
}
