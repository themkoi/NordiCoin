#[cfg(feature = "debug")]
pub use defmt::{info, warn, error};

#[cfg(not(feature = "debug"))]
pub use crate::{info, warn, error};

#[cfg(feature = "debug")]
pub use defmt::Debug2Format;

#[cfg(feature = "debug")]
pub use defmt::Format;

#[cfg(not(feature = "debug"))]
pub trait Format {}

#[cfg(not(feature = "debug"))]
impl<T> Format for T {}

#[cfg(not(feature = "debug"))]
pub struct Debug2Format<T>(pub T);

#[cfg(not(feature = "debug"))]
impl<T: core::fmt::Debug> core::fmt::Debug for Debug2Format<T> {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        core::fmt::Debug::fmt(&self.0, f)
    }
}

pub use nrf_sdc::{self as sdc, mpsl};
pub use nrf_sdc::SoftdeviceController;
pub use crate::config::*;
pub use crate::peripherals::device_info::*;
pub use embassy_nrf::pac;
pub use trouble_host::prelude::*;
pub use crate::peripherals::led::*;
pub use crate::peripherals::peripherals_task::*;
pub use embassy_time::Duration;
pub use embassy_time::Timer;
pub use embassy_futures::select::select;
pub use embassy_futures::join::join;
pub use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
pub use embassy_sync::channel::Channel;
pub use crate::other::*;
pub use embassy_nrf::gpio::Input;
pub use embassy_sync::mutex::Mutex;
pub use embassy_nrf::{bind_interrupts, config::LfclkSource, gpio::Pull, rng};
