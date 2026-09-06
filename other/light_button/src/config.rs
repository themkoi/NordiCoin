use crate::prelude::*;

// LED
pub const LED_BLINK_MS: Duration = Duration::from_millis(5);
pub const LED_BLINK_FOR_ON_MS: Duration = Duration::from_millis(50);
pub const LED_BLINK_FOR_OFF_MS: Duration = Duration::from_millis(500);

pub const TARGET_ADDRESS: [u8; 6] = [0xAC, 0x15, 0x18, 0xD6, 0xAE, 0x4E];

// Button
pub const BUTTON_HOLD_TIME: Duration = Duration::from_secs(5);
