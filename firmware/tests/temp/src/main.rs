#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::bind_interrupts;
use embassy_nrf::temp::Temp;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

bind_interrupts!(struct Irqs {
    TEMP => embassy_nrf::temp::InterruptHandler;
});

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    let mut temp = Temp::new(p.TEMP, Irqs);

    info!("Temperature sensor test");
    info!("Not working, manual offset would be needed, otherwise it's too innacurate");

    loop {
        let temp_c = temp.read().await.to_num::<f32>();
        
        info!("Die temperature = {} °C", temp_c);
        Timer::after(Duration::from_secs(1)).await;
    }
}
