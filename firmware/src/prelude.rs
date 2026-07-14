#[cfg(feature = "debug")]
pub use defmt::{info, warn, error};

#[cfg(not(feature = "debug"))]
pub use crate::{info, warn, error};

pub use nrf_sdc::{self as sdc, mpsl};
pub use nrf_sdc::SoftdeviceController;
pub use crate::ble::*;
pub use crate::config::*;
pub use crate::peripherals::device_info::*;
pub use embassy_nrf::pac;
pub use trouble_host::prelude::*;
pub use embassy_futures::join::join;
pub use crate::peripherals::adc::*;
pub use embassy_time::Duration;
pub use embassy_time::Timer;
pub use embassy_futures::select::select;
pub use defmt::Debug2Format;
