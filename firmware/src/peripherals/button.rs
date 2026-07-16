use crate::prelude::*;

pub async fn manage_button(mut button: Input<'_>, flash: &'static FlashStorage) {
    loop {
        button.wait_for_high().await;
        info!("Button clicked");
        LED_CHANNEL.send(LedCommand::Blink).await;
        match select(button.wait_for_low(), Timer::after(BUTTON_HOLD_TIME)).await {
            embassy_futures::select::Either::First(_) => {
                info!("Button released early, stopping any buzzing");
                PWM_CHANNEL.send(PwmCommand::TurnOnFor(0)).await;
                LED_CHANNEL.send(LedCommand::TurnOnFor(0)).await;
            }
            embassy_futures::select::Either::Second(_) => {
                info!("Button released after holding, removing bonding");
                let mut flash_data = flash.read().await;
                LED_CHANNEL.send(LedCommand::TurnOnFor(2)).await; // Fake it when it's not updating too, just to give feedback
                if flash_data.bonded {
                    info!("Device is bonded but button was hold, unbonding!");
                    flash_data.bonded = false;
                    flash.save(&flash_data).await;
                    Timer::after_millis(2500).await;
                    info!("Rebooting!");
                    Timer::after_millis(50).await;
                    cortex_m::peripheral::SCB::sys_reset();
                }
                if button.is_high() {
                    button.wait_for_low().await;
                }
            }
        }
        Timer::after_millis(100).await;
    }
}
