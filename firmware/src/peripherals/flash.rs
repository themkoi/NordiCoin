use core::cell::RefCell;

use embassy_nrf::nvmc::Nvmc;
use embassy_nrf::peripherals::NVMC;
use embassy_nrf::Peri;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embedded_storage::nor_flash::{NorFlash, ReadNorFlash};

use crate::config::BLE_NAME_LENGTH_MAX;

#[derive(Debug)]
#[repr(C)]
pub struct FlashData {
    pub name: [u8; BLE_NAME_LENGTH_MAX],
}

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

    pub async fn save(&self, data: &FlashData) -> Result<(), &'static str> {
        let guard = FLASH_STORAGE.lock().await;
        let mut nvmc_ref = guard.borrow_mut();
        let nvmc = nvmc_ref.as_mut().ok_or("Flash not initialized")?;
        let off = core::ptr::addr_of!(storage_start) as u32;

        nvmc.erase(off, off + core::mem::size_of::<FlashData>() as u32)
            .map_err(|_| "Flash erase failed")?;

        let bytes = unsafe {
            core::slice::from_raw_parts(
                data as *const FlashData as *const u8,
                core::mem::size_of::<FlashData>(),
            )
        };
        nvmc.write(off, bytes).map_err(|_| "Flash write failed")?;

        Ok(())
    }

    pub async fn read(&self) -> Result<FlashData, &'static str> {
        let guard = FLASH_STORAGE.lock().await;
        let mut nvmc_ref = guard.borrow_mut();
        let nvmc = nvmc_ref.as_mut().ok_or("Flash not initialized")?;
        let off = core::ptr::addr_of!(storage_start) as u32;

        let mut buf = [0u8; core::mem::size_of::<FlashData>()];
        nvmc.read(off, &mut buf).map_err(|_| "Flash read failed")?;

        let data = unsafe {
            core::mem::transmute::<[u8; core::mem::size_of::<FlashData>()], FlashData>(buf)
        };

        Ok(data)
    }
}
