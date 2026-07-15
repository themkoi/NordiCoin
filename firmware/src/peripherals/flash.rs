use crate::config::BLE_DEFAULT_TX_POWER;

use core::cell::RefCell;

use crc::{Crc, CRC_32_ISCSI};
use embassy_nrf::nvmc::Nvmc;
use embassy_nrf::peripherals::NVMC;
use embassy_nrf::Peri;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embedded_storage::nor_flash::{NorFlash, ReadNorFlash};
use postcard::experimental::max_size::MaxSize;
use serde::{Deserialize, Serialize};
use crate::prelude::*;

#[derive(Debug, Serialize, Deserialize, MaxSize)]
#[repr(C)]
pub struct FlashData {
    pub bonded: bool,
    pub tx_power: i8,
}

/// Convert an i8 tx_power value to a trouble_host TxPower enum.
/// Returns the default (ZerodBm) if the value doesn't match any valid level.
pub fn tx_power_from_i8(value: i8) -> trouble_host::advertise::TxPower {
    match value {
        -40 => trouble_host::advertise::TxPower::Minus40dBm,
        -20 => trouble_host::advertise::TxPower::Minus20dBm,
        -16 => trouble_host::advertise::TxPower::Minus16dBm,
        -12 => trouble_host::advertise::TxPower::Minus12dBm,
        -8 => trouble_host::advertise::TxPower::Minus8dBm,
        -4 => trouble_host::advertise::TxPower::Minus4dBm,
        0 => trouble_host::advertise::TxPower::ZerodBm,
        2 => trouble_host::advertise::TxPower::Plus2dBm,
        3 => trouble_host::advertise::TxPower::Plus3dBm,
        4 => trouble_host::advertise::TxPower::Plus4dBm,
        5 => trouble_host::advertise::TxPower::Plus5dBm,
        6 => trouble_host::advertise::TxPower::Plus6dBm,
        7 => trouble_host::advertise::TxPower::Plus7dBm,
        8 => trouble_host::advertise::TxPower::Plus8dBm,
        10 => trouble_host::advertise::TxPower::Plus10dBm,
        12 => trouble_host::advertise::TxPower::Plus12dBm,
        14 => trouble_host::advertise::TxPower::Plus14dBm,
        16 => trouble_host::advertise::TxPower::Plus16dBm,
        18 => trouble_host::advertise::TxPower::Plus18dBm,
        20 => trouble_host::advertise::TxPower::Plus20dBm,
        _ => trouble_host::advertise::TxPower::ZerodBm,
    }
}

impl Default for FlashData {
    fn default() -> Self {
        Self {
            bonded: false,
            tx_power: BLE_DEFAULT_TX_POWER,
        }
    }
}

const FLASH_BUF_SIZE: usize = FlashData::POSTCARD_MAX_SIZE;

extern "C" {
    static storage_start: u8;
    static storage_end: u8;
}

static FLASH_STORAGE: Mutex<CriticalSectionRawMutex, RefCell<Option<Nvmc<'static>>>> =
    Mutex::new(RefCell::new(None));

pub struct FlashStorage {
    _private: (),
}

impl FlashStorage {
    pub async fn new(nvmc: Peri<'static, NVMC>) -> Self {
        let nvmc = Nvmc::new(nvmc);
        let guard = FLASH_STORAGE.lock().await;
        guard.borrow_mut().replace(nvmc);
        FlashStorage { _private: () }
    }

    pub async fn save(&self, data: &FlashData) {
        let guard = FLASH_STORAGE.lock().await;
        let mut nvmc_ref = guard.borrow_mut();
        let nvmc = nvmc_ref.as_mut().unwrap();
        let off = core::ptr::addr_of!(storage_start) as u32;

        let page_end = off + (core::ptr::addr_of!(storage_end) as u32 - off);
        nvmc.erase(off, page_end)
            .map_err(|_| "Flash erase failed")
            .unwrap();

        let mut buf = [0u8; FLASH_BUF_SIZE];
        let crc = Crc::<u32>::new(&CRC_32_ISCSI);
        let used = postcard::to_slice_crc32(&data, &mut buf, crc.digest())
            .map_err(|_| "Serialization failed")
            .unwrap();
        nvmc.write(off, used)
            .map_err(|_| "Flash write failed")
            .unwrap();
    }

    pub async fn read(&self) -> FlashData {
        let guard = FLASH_STORAGE.lock().await;
        let mut nvmc_ref = guard.borrow_mut();
        let nvmc = nvmc_ref.as_mut().unwrap();
        let off = core::ptr::addr_of!(storage_start) as u32;

        let mut buf = [0u8; FLASH_BUF_SIZE];
        nvmc.read(off, &mut buf).ok().unwrap_or_default();

        let crc = Crc::<u32>::new(&CRC_32_ISCSI);
        postcard::from_bytes_crc32(&buf, crc.digest()).unwrap_or_default()
    }
}
