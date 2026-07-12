#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Flex, OutputDrive};
use embassy_nrf::pac::gpio::vals::{Dir, Input, Pull};
use embassy_nrf::pac::P0;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

pub struct LedController {
    pin_nr: u8,
    pin: Flex<'static>,
}

impl LedController {
    pub fn new(pin_nr: u8, pin: embassy_nrf::Peri<'static, embassy_nrf::peripherals::P0_20>) -> Self {
        Self {
            pin_nr,
            pin: Flex::new(pin),
        }
    }

    pub fn turn_on(&mut self) {
        self.pin.set_as_output(OutputDrive::HighDrive);
        self.pin.set_low();
    }

    pub fn turn_off(&mut self) {
        P0.pin_cnf(self.pin_nr as usize).write(|w| {
            w.set_dir(Dir::Input);
            w.set_input(Input::Disconnect);
            w.set_pull(Pull::Disabled);
        });
    }
}

const BLINK_INTERVAL_MS: u64 = 500;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    let mut led = LedController::new(20, p.P0_20);

    info!("LED test on P0.20");

    for _ in 0..10 {
        led.turn_on();
        info!("LED on");
        Timer::after(Duration::from_millis(BLINK_INTERVAL_MS)).await;

        led.turn_off();
        info!("LED off (high-impedance)");
        Timer::after(Duration::from_millis(BLINK_INTERVAL_MS)).await;
    }
    loop {
        Timer::after(Duration::from_secs(120)).await;
    }
}
