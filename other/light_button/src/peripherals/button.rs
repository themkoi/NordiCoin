use crate::ble;
use crate::prelude::*;
use embassy_executor::Spawner;
use embassy_futures::select::{select, Either};
use embassy_time::{Duration, Timer};

pub async fn manage_button(_spawner: Spawner, mut button: Input<'_>) {
    loop {
        // Wait for the initial press edge
        button.wait_for_high().await;

        // --- Debounce Check ---
        // Wait a short duration to let contact bounce settle
        Timer::after(Duration::from_millis(20)).await;
        if button.is_low() {
            // If it went back low, it was just electrical noise. Ignore and loop again.
            continue;
        }
        // ----------------------

        info!("Button clicked & debounced");
        LED_CHANNEL.send(LedCommand::Blink).await;

        // Select between the button being released early or the hold timer expiring
        match select(button.wait_for_low(), Timer::after(BUTTON_HOLD_TIME)).await {
            Either::First(_) => {
                info!("Button released early (Short Press)");
                LED_CHANNEL.send(LedCommand::TurnOnFor(0)).await;

                // Send 0x00 through the global channel
                let press_data: u8 = 0x00;
                ble::BLE_CHANNEL.send(press_data).await;
            }

            Either::Second(_) => {
                info!("Button held long enough (Long Press), waiting for release...");
                LED_CHANNEL.send(LedCommand::TurnOnFor(2)).await;

                // Send 0x01 through the global channel
                let hold_data: u8 = 0x01;
                ble::BLE_CHANNEL.send(hold_data).await;
                // Ensure we wait until the user actually lets go of the button
                if button.is_high() {
                    button.wait_for_low().await;
                }
            }
        }

        // Cooldown/debounce delay before listening for the next click cycle
        Timer::after(Duration::from_millis(100)).await;
    }
}
