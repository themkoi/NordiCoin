use embassy_nrf::gpio::{Flex, OutputDrive};
use embassy_nrf::pac::gpio::vals::{Dir, Input, Pull};
use embassy_nrf::pac::P0;

use crate::prelude::*;

pub enum LedCommand {
    TurnOff,
    Blink,
    BlinkFor(u8),
}

pub static LED_CHANNEL: Channel<CriticalSectionRawMutex, LedCommand, 1> = Channel::new();

pub struct LedController {
    pin_nr: u8,
    pin: Flex<'static>,
}

impl LedController {
    pub fn new(
        pin_nr: u8,
        pin: embassy_nrf::Peri<'static, embassy_nrf::peripherals::P0_20>,
    ) -> Self {
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

#[embassy_executor::task]
pub async fn led_task(mut controller: LedController) {
    loop {
        match LED_CHANNEL.receive().await {
            LedCommand::TurnOff => {
                controller.turn_off();
            }
            LedCommand::Blink => {
                controller.turn_on();
                Timer::after(LED_BLINK_MS).await;
                controller.turn_off();
            }
            LedCommand::BlinkFor(count) => {
                for _ in 0..count {
                    controller.turn_on();
                    Timer::after(LED_BLINK_FOR_ON_MS).await;
                    controller.turn_off();
                    if LED_CHANNEL
                        .try_receive()
                        .is_ok_and(|c| matches!(c, LedCommand::TurnOff))
                    {
                        break;
                    }
                    Timer::after(LED_BLINK_FOR_OFF_MS).await;
                }
            }
        }
    }
}
