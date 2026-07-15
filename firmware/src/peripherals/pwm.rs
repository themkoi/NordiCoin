use embassy_nrf::gpiote::{OutputChannel, OutputChannelPolarity};
use embassy_nrf::peripherals::{PPI_CH0, PPI_CH1, TIMER1};
use embassy_nrf::ppi::Ppi;
use embassy_nrf::timer::{Frequency, Timer};
use embassy_time::Timer as EmbassyTimer;

use crate::config::*;
use crate::prelude::*;

#[derive(PartialEq)]
pub enum PwmCommand {
    TurnOff,
    TurnOnFor(u8), // s
}

pub static PWM_CHANNEL: Channel<CriticalSectionRawMutex, PwmCommand, 1> = Channel::new();

pub struct PwmController {
    timer: Timer<'static>,
    _gpiote: OutputChannel<'static>,
    ppi_set: Ppi<'static, PPI_CH0, 1, 1>,
    ppi_clr: Ppi<'static, PPI_CH1, 1, 1>,
}

impl PwmController {
    pub fn new(
        timer: embassy_nrf::Peri<'static, TIMER1>,
        ppi_ch0: embassy_nrf::Peri<'static, PPI_CH0>,
        ppi_ch1: embassy_nrf::Peri<'static, PPI_CH1>,
        gpiote_ch0: embassy_nrf::Peri<'static, embassy_nrf::peripherals::GPIOTE_CH0>,
        pin: embassy_nrf::Peri<'static, embassy_nrf::gpio::AnyPin>,
    ) -> Self {
        let timer = Timer::new(timer);
        timer.set_frequency(Frequency::F16MHz);

        let period = 16000; // 1 kHz PWM at F16MHz
        timer.cc(0).write(period);
        timer.cc(1).write(0); // 0% duty initially

        timer.cc(0).short_compare_clear();

        let gpiote = OutputChannel::new(
            gpiote_ch0,
            pin,
            embassy_nrf::gpio::Level::Low,
            embassy_nrf::gpio::OutputDrive::HighDrive,
            OutputChannelPolarity::Toggle,
        );

        let ppi_set = Ppi::new_one_to_one(ppi_ch0, timer.cc(0).event_compare(), gpiote.task_set());
        let ppi_clr = Ppi::new_one_to_one(ppi_ch1, timer.cc(1).event_compare(), gpiote.task_clr());

        let mut ppi_set = ppi_set;
        ppi_set.enable();
        let mut ppi_clr = ppi_clr;
        ppi_clr.enable();

        timer.start();

        PwmController {
            timer,
            _gpiote: gpiote,
            ppi_set,
            ppi_clr,
        }
    }

    // Call `set_duty_percent()` again after.
    pub fn set_frequency(&mut self, hz: u32) {
        let period = 16_000_000 / hz;
        self.timer.stop();
        self.timer.cc(0).write(period);
        self.timer.clear();
        self.timer.start();
    }

    // Turn off PWM output to save power.
    pub fn turn_off(&mut self) {
        self.timer.stop();
        self.ppi_set.disable();
        self.ppi_clr.disable();
    }

    pub fn turn_on(&mut self) {
        self.timer.clear();
        self.ppi_set.enable();
        self.ppi_clr.enable();
        self.timer.start();
    }

    // 100 maps to 0!
    pub fn set_duty_percent(&mut self, mut percent: u8) {
        if percent == 100 {
            percent = 0;
        }
        let period = self.timer.cc(0).read();
        let duty = (period as u32 * percent as u32) / 100;
        self.timer.cc(1).write(duty);
    }

    pub async fn sweep(&mut self) {
        let start = PWM_BASE_FREQ.wrapping_sub(PWM_FREQ_TOLERANCE as u32);
        let end = PWM_BASE_FREQ.wrapping_add(PWM_FREQ_TOLERANCE as u32);

        // Sweep up
        let mut freq = start;
        while freq <= end {
            self.set_frequency(freq);
            self.set_duty_percent(PWM_BASE_DUTY);
            info!("PWM: freq={} Hz  duty={} %", freq, PWM_BASE_DUTY);
            EmbassyTimer::after(PWM_BASE_DELAY_MS).await;
            self.set_duty_percent(0);
            EmbassyTimer::after(PWM_BASE_DELAY_MS).await;
            freq = freq.wrapping_add(PWM_FREQ_STEP as u32);
        }
        // Sweep down
        freq = end;
        while freq >= start {
            self.set_frequency(freq);
            self.set_duty_percent(PWM_BASE_DUTY);
            info!("PWM: freq={} Hz  duty={} %", freq, PWM_BASE_DUTY);
            EmbassyTimer::after(PWM_BASE_DELAY_MS).await;
            self.set_duty_percent(0);
            EmbassyTimer::after(PWM_BASE_DELAY_MS).await;
            freq = freq.wrapping_sub(PWM_FREQ_STEP as u32);
        }
    }
}

#[embassy_executor::task]
pub async fn pwm_task(mut controller: PwmController) {
    controller.turn_off();
    loop {
        match PWM_CHANNEL.receive().await {
            PwmCommand::TurnOff => {
                controller.turn_off();
            }
            PwmCommand::TurnOnFor(seconds) => {
                select(
                    async {
                        EmbassyTimer::after_secs(seconds.into()).await;
                        info!("Timer runned out for pwm");
                    },
                    async {
                        select(
                            async {
                                PWM_CHANNEL.ready_to_receive().await;
                            },
                            async {
                                loop {
                                    controller.sweep().await;
                                }
                            },
                        )
                        .await;
                    },
                )
                .await;
                controller.turn_off();
            }
        }
    }
}
