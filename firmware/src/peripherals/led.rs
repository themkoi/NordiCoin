use embassy_nrf::gpio::{Flex, OutputDrive};
use embassy_nrf::pac::gpio::vals::{Dir, Input, Pull};
use embassy_nrf::pac::P0;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;

use crate::prelude::*;

#[derive(Clone)]
pub enum LedCommand {
    TurnOff,
    Blink,
    TurnOnFor(u8), // seconds
}

pub static LED_CHANNEL: Channel<CriticalSectionRawMutex, LedCommand, 1> = Channel::new();

pub struct LedController {
    pin_nr: u8,
    pin: Mutex<CriticalSectionRawMutex, Flex<'static>>,
}

impl LedController {
    pub fn new(
        pin_nr: u8,
        pin: embassy_nrf::Peri<'static, embassy_nrf::peripherals::P0_20>,
    ) -> Self {
        Self {
            pin_nr,
            pin: Mutex::new(Flex::new(pin)),
        }
    }

    pub async fn turn_on(&self) {
        let mut pin = self.pin.lock().await;
        pin.set_as_output(OutputDrive::HighDrive);
        pin.set_low();
    }

    pub async fn turn_off(&self) {
        let pin_nr = self.pin_nr;
        let _pin = self.pin.lock().await;
        P0.pin_cnf(pin_nr as usize).write(|w| {
            w.set_dir(Dir::Input);
            w.set_input(Input::Disconnect);
            w.set_pull(Pull::Disabled);
        });
    }

    pub async fn blink(&self) {
        self.turn_on().await;
        Timer::after(LED_BLINK_MS).await;
        self.turn_off().await;
    }
}

#[embassy_executor::task]
pub async fn led_task(controller: LedController) {
    controller.turn_off().await;
    loop {
        match LED_CHANNEL.receive().await {
            LedCommand::TurnOff => {
                controller.turn_off().await;
            }
            LedCommand::Blink => {
                controller.blink().await;
            }
            LedCommand::TurnOnFor(seconds) => {
                select(
                    async {
                        Timer::after_secs(seconds.into()).await;
                        info!("Timer runned out for led");
                    },
                    async {
                        select(
                            async {
                                loop {
                                    LED_CHANNEL.ready_to_receive().await;
                                    if let Ok(v) = LED_CHANNEL.try_peek() {
                                        if matches!(v, LedCommand::Blink) {
                                            controller.blink().await;
                                        } else {
                                            info!("Received another message in led");
                                            break;
                                        }
                                    }
                                }
                            },
                            async {
                                loop {
                                    controller.turn_on().await;
                                    Timer::after(LED_BLINK_FOR_ON_MS).await;
                                    controller.turn_off().await;
                                    Timer::after(LED_BLINK_FOR_OFF_MS).await;
                                }
                            },
                        )
                        .await;
                    },
                )
                .await;
                controller.turn_off().await;
            }
        }
    }
}
