use crate::peripherals::button::manage_button;
use crate::prelude::*;

#[embassy_executor::task]
pub async fn peripherals_task(
    pwm_controller: PwmController,
    led_controller: LedController,
    button: Input<'static>,
    flash: &'static FlashStorage,
) {
    let pwm_future = manage_pwm(pwm_controller);
    let led_future = manage_led(led_controller);
    let button_future = manage_button(button, flash);
    join(pwm_future, join(led_future, button_future)).await;
}
