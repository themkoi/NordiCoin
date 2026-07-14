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

#[derive(Debug, Serialize, Deserialize, MaxSize)]
#[repr(C)]
pub struct FlashData {
    pub bonded: bool,
}

impl Default for FlashData {
    fn default() -> Self {
        Self { bonded: false }
    }
}

const FLASH_BUF_SIZE: usize = FlashData::POSTCARD_MAX_SIZE;

extern "C" {
    static storage_start: u8;
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

        nvmc.erase(off, off + FLASH_BUF_SIZE as u32)
            .map_err(|_| "Flash erase failed").unwrap();

        let mut buf = [0u8; FLASH_BUF_SIZE];
        let crc = Crc::<u32>::new(&CRC_32_ISCSI);
        let used = postcard::to_slice_crc32(&data, &mut buf, crc.digest())
            .map_err(|_| "Serialization failed").unwrap();
        nvmc.write(off, used).map_err(|_| "Flash write failed").unwrap();
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
