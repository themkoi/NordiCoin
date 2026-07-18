#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::gpiote::{OutputChannel, OutputChannelPolarity};
use embassy_nrf::peripherals::{PPI_CH0, PPI_CH1};
use embassy_nrf::ppi::Ppi;
use embassy_nrf::timer::{Frequency, Timer};
use embassy_time::{Duration, Timer as EmbassyTimer};
use {defmt_rtt as _, panic_probe as _};

pub struct PwmController {
    timer: Timer<'static>,
    _gpiote: OutputChannel<'static>,
    ppi_set: Ppi<'static, PPI_CH0, 1, 1>,
    ppi_clr: Ppi<'static, PPI_CH1, 1, 1>,
}

impl PwmController {
    pub fn new(
        timer: embassy_nrf::Peri<'static, embassy_nrf::peripherals::TIMER0>,
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
        self.timer.regs().tasks_shutdown().write_value(1);
        self.timer.clear();
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
}

const BASE_FREQ: u32 = 4950;
const BASE_DUTY: u8 = 35;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut c = embassy_nrf::config::Config::default();
    c.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(c);

    let mut pwm_controller =
        PwmController::new(p.TIMER0, p.PPI_CH0, p.PPI_CH1, p.GPIOTE_CH0, p.P0_18.into());

    info!("Starting!");
    loop {
        pwm_controller.set_frequency(BASE_FREQ);
        pwm_controller.set_duty_percent(BASE_DUTY);
        EmbassyTimer::after_secs(5).await;

        info!("Turning it off");
        EmbassyTimer::after_secs(1).await;
        pwm_controller.turn_off();
        info!("It's off");

        EmbassyTimer::after_secs(3).await;

        info!("Turning it on");
        EmbassyTimer::after_secs(1).await;
        pwm_controller.turn_on();
        info!("It's on");
    }
}
