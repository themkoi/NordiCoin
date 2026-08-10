#![no_std]
#![no_main]

use embassy_executor::Spawner;
use {defmt_rtt as _, panic_probe as _};

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let config = embassy_nrf::config::Config::default();
    let _p = embassy_nrf::init(config);

    // _spawner.spawn(task().unwrap());
}

// 52 Bytes!
/*
#[embassy_executor::task]
pub async fn task() {

}
*/
