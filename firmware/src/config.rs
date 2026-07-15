use crate::prelude::*;

// BLE
pub const SDC_MEM_SIZE: usize = 4696;
pub const BLE_NAME_NOT_BONDED: &'static str = "NordiCoin-";
pub const BLE_CONN_TIMEOUT_NOT_BONDED: Duration = Duration::from_secs(30);
pub const BLE_CONN_TIMEOUT_BONDED: Duration = Duration::from_secs(4);
pub const BLE_DEFAULT_TX_POWER: i8 = trouble_host::advertise::TxPower::Minus40dBm as i8;

// LED
pub const LED_BLINK_MS: Duration = Duration::from_millis(0);
pub const LED_BLINK_FOR_ON_MS: Duration = Duration::from_millis(50);
pub const LED_BLINK_FOR_OFF_MS: Duration = Duration::from_millis(500);

// PWM
pub const PWM_BASE_FREQ: u32 = 4950;
pub const PWM_FREQ_TOLERANCE: u16 = 300;
pub const PWM_FREQ_STEP: u16 = 300;
pub const PWM_BASE_DUTY: u8 = 50;
pub const PWM_BASE_DELAY_MS: Duration = Duration::from_millis(300);

