#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

#[embassy_executor::task]
async fn blink_task(mut led: Output<'static>) -> ! {
    loop {
        led.toggle();
        info!("LED toggled");
        Timer::after(Duration::from_millis(500)).await;
    }
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let p = embassy_nrf::init(Default::default());
    info!("Blinky starting on nRF52805");

    // let led = Output::new(p.P0_17, Level::High, OutputDrive::Standard);

    // spawner.spawn(blink_task(led).unwrap());

    loop {
        info!("Fucking work");
        Timer::after(Duration::from_secs(1)).await;
    }
}
