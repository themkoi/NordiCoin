#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::bind_interrupts;
use embassy_nrf::rng::{InterruptHandler, Rng};
use embassy_nrf::peripherals::RNG;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

async fn random_u32(rng: &mut Rng<'_, embassy_nrf::mode::Async>) -> u32 {
    let mut buf = [0u8; 4];
    rng.fill_bytes(&mut buf).await;
    u32::from_ne_bytes(buf)
}

async fn random_u64(rng: &mut Rng<'_, embassy_nrf::mode::Async>) -> u64 {
    let mut buf = [0u8; 8];
    rng.fill_bytes(&mut buf).await;
    u64::from_ne_bytes(buf)
}

bind_interrupts!(struct Irqs {
    RNG => InterruptHandler<RNG>;
});

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    let mut rng = Rng::new(p.RNG, Irqs);

    info!("RNG test started");

    loop {
        for i in 0..4 {
            let val = random_u32(&mut rng).await;
            info!("Random u32[{}] = 0x{:08X}", i, val);
        }

        for i in 0..4 {
            let val = random_u64(&mut rng).await;
            info!("Random u64[{}] = 0x{:016X}", i, val);
        }

        let mut bytes = [0u8; 16];
        rng.fill_bytes(&mut bytes).await;
        info!("Random bytes: {:?}", bytes);
        Timer::after(Duration::from_secs(10)).await;
    }
}
