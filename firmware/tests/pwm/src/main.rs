#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::gpiote::{OutputChannel, OutputChannelPolarity};
use embassy_nrf::ppi::Ppi;
use embassy_nrf::peripherals::{PPI_CH0, PPI_CH1};
use embassy_nrf::timer::{Frequency, Timer};
use embassy_time::{Duration, Timer as EmbassyTimer};
use {defmt_rtt as _, panic_probe as _};

pub struct PwmController {
    timer: Timer<'static>,
    gpiote: OutputChannel<'static>,
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
        // Create timer
        let timer = Timer::new(timer);
        timer.set_frequency(Frequency::F16MHz);

        // Set period (CC[0]) and initial duty (CC[1])
        let period = 16000; // 1 kHz PWM (16MHz / 16000 = 1kHz)
        timer.cc(0).write(period);
        timer.cc(1).write(period / 2); // 50% duty initially

        // Enable shortcut: when CC[0] compare matches, auto-clear the timer counter.
        // This makes the timer run from 0..period continuously.
        timer.cc(0).short_compare_clear();

        // Single GPIOTE output channel with Toggle polarity.
        // task_set() and task_clr() are used as distinct PPI targets.
        let gpiote = OutputChannel::new(
            gpiote_ch0,
            pin,
            embassy_nrf::gpio::Level::Low,
            embassy_nrf::gpio::OutputDrive::HighDrive,
            OutputChannelPolarity::Toggle,
        );

        // PPI CH0: TIMER CC[0] (period end) → SET task → pin goes HIGH at start of each period
        let ppi_set = Ppi::new_one_to_one(
            ppi_ch0,
            timer.cc(0).event_compare(),
            gpiote.task_set(),
        );
        // PPI CH1: TIMER CC[1] (duty point) → CLR task → pin goes LOW at duty cycle
        let ppi_clr = Ppi::new_one_to_one(
            ppi_ch1,
            timer.cc(1).event_compare(),
            gpiote.task_clr(),
        );

        // Enable PPI channels
        let mut ppi_set = ppi_set;
        ppi_set.enable();
        let mut ppi_clr = ppi_clr;
        ppi_clr.enable();

        // Start the timer
        timer.start();

        PwmController {
            timer,
            gpiote,
            ppi_set,
            ppi_clr,
        }
    }

    /// Set duty cycle by percentage (0..=100).
    ///
    /// The pin is HIGH from counter=0 to counter=duty, and LOW from counter=duty to counter=period.
    pub fn set_duty_percent(&mut self, percent: u8) {
        let period = self.timer.cc(0).read();
        let duty = (period as u32 * percent as u32) / 100;
        self.timer.cc(1).write(duty);
        info!("PWM duty cycle: {}%", percent);
    }
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let config = embassy_nrf::config::Config::default();
    let p = embassy_nrf::init(config);

    let mut pwm_controller = PwmController::new(
        p.TIMER0,
        p.PPI_CH0,
        p.PPI_CH1,
        p.GPIOTE_CH0,
        p.P0_18.into(),
    );

    loop {
        // Sweep from 0% to 100% in 5% steps
        for duty in (0..=100).step_by(5) {
            pwm_controller.set_duty_percent(duty);
            EmbassyTimer::after(Duration::from_millis(2000)).await;
        }
        // Sweep back from 100% to 0% in 5% steps
        for duty in (0..=100).step_by(5).rev() {
            pwm_controller.set_duty_percent(duty);
            EmbassyTimer::after(Duration::from_millis(2000)).await;
        }
    }
}
