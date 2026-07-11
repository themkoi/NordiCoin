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
        let period = 16000; // 1 kHz PWM at F16MHz (16MHz / 16000 = 1kHz)
        timer.cc(0).write(period);
        timer.cc(1).write(0); // 0% duty initially

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
        let ppi_set = Ppi::new_one_to_one(ppi_ch0, timer.cc(0).event_compare(), gpiote.task_set());
        // PPI CH1: TIMER CC[1] (duty point) → CLR task → pin goes LOW at duty cycle
        let ppi_clr = Ppi::new_one_to_one(ppi_ch1, timer.cc(1).event_compare(), gpiote.task_clr());

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

    /// Set PWM frequency in Hz.
    ///
    /// The timer clock is 16 MHz (HFCLK). The frequency is derived from:
    /// `fPWM = 16_000_000 / period`, where `period` is the CC[0] value.
    ///
    /// Valid range: ~488 Hz (period=32767) to 16 MHz (period=1).
    ///
    /// Note: changing the frequency resets CC[1] (duty) to 0. Call
    /// `set_duty_percent()` again after this to restore your desired duty.
    pub fn set_frequency(&mut self, hz: u32) {
        let period = 16_000_000 / hz;
        self.timer.cc(0).write(period);
        info!("PWM frequency: {} Hz", hz);
    }

    // 100 is 0!
    pub fn set_duty_percent(&mut self, mut percent: u8) {
        if percent == 100 {
            percent = 0;
        }
        let period = self.timer.cc(0).read();
        let duty = (period as u32 * percent as u32) / 100;
        self.timer.cc(1).write(duty);
    }
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let config = embassy_nrf::config::Config::default();
    let p = embassy_nrf::init(config);

    let mut pwm_controller =
        PwmController::new(p.TIMER0, p.PPI_CH0, p.PPI_CH1, p.GPIOTE_CH0, p.P0_18.into());

    loop {
        /*
        for freq in (500..=20000).step_by(500) {
            info!("Setting freq: {} Hz", freq);
            pwm_controller.set_frequency(freq);
            EmbassyTimer::after(Duration::from_millis(100)).await;

            for duty in (1..=99).step_by(1) {
                pwm_controller.set_duty_percent(duty);

                // Give it a moment to run at this specific config
                EmbassyTimer::after(Duration::from_millis(100)).await;
            }
        }
        */

        // const FREQUENCIES: &[u32] = &[2000, 3500, 4000, 4500, 11500];
        // const FREQUENCIES: &[u32] = &[4000, 4250, 4500, 4750, 5000, 6000];
        const FREQUENCIES: &[u32] = &[3500, 3750, 4000, 4100, 4200, 4250];
        const FIXED_DUTY_PERCENT: u8 = 50;
        const DELAY: Duration = Duration::from_millis(500);

        for &freq in FREQUENCIES {
            info!("Starting test for frequency: {} Hz", freq);
            pwm_controller.set_frequency(freq);

            for i in 0..10 {
                info!("  Beep {}/10 at {} Hz", i + 1, freq);

                pwm_controller.set_duty_percent(FIXED_DUTY_PERCENT);
                EmbassyTimer::after(DELAY).await;

                pwm_controller.set_duty_percent(0);
                EmbassyTimer::after(DELAY).await;
            }

            EmbassyTimer::after(DELAY).await;
            EmbassyTimer::after(DELAY).await;
            EmbassyTimer::after(DELAY).await;
        }
    }
}
// 2000, 3500, 4000, 4500, 11500
//
