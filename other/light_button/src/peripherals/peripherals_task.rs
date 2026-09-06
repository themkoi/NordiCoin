use embassy_executor::Spawner;
use crate::ble;
use crate::peripherals::button::manage_button;
use crate::prelude::*;

#[embassy_executor::task]
pub async fn peripherals_task(
    spawner: Spawner,
    led_controller: LedController,
    button: Input<'static>,
) {
    let led_future = manage_led(led_controller);

    let button_future = manage_button(
        spawner,
        button,
    );

    join(
        led_future,
        button_future,
    )
    .await;
}