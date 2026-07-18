use crate::prelude::*;

// BLE
pub const SDC_MEM_SIZE: usize = 4696;
pub const BLE_NAME_NOT_BONDED: &'static str = "NordiCoin-";
pub const BLE_CONN_TIMEOUT_NOT_BONDED: Duration = Duration::from_secs(30);
pub const BLE_CONN_TIMEOUT_BONDED: Duration = Duration::from_secs(4);
pub const BLE_DEFAULT_TX_POWER: i8 = trouble_host::advertise::TxPower::ZerodBm as i8;
pub const BLE_REFRESH_BATTERY: Duration = Duration::from_secs(60 * 60 * 2); // 2h
pub const BLINK_ON_CONNECTION: bool = true; // Could be a feature to save a few bytes but nah
// Configuring these impacts battery life a lot, but also how easy it is to connect to it
pub const ADV_INTERVAL_MIN_MS: Duration = Duration::from_millis(5000);
pub const ADV_INTERVAL_MAX_MS: Duration = Duration::from_millis(5100);

// LED
pub const LED_BLINK_MS: Duration = Duration::from_millis(5);
pub const LED_BLINK_FOR_ON_MS: Duration = Duration::from_millis(50);
pub const LED_BLINK_FOR_OFF_MS: Duration = Duration::from_millis(500);

// PWM
pub const PWM_BASE_FREQ: u32 = 4950;
pub const PWM_FREQ_TOLERANCE: u16 = 400;
pub const PWM_FREQ_STEP: u16 = 200;
pub const PWM_BASE_DUTY: u8 = 50;
pub const PWM_BASE_DELAY_MS: Duration = Duration::from_millis(100);

// Button
pub const BUTTON_HOLD_TIME: Duration = Duration::from_secs(5);
