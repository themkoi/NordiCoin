#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::config::LfclkSource;
use embassy_nrf::nvmc::Nvmc;
use embedded_storage::nor_flash::{NorFlash, ReadNorFlash};
use {defmt_rtt as _, panic_probe as _};

#[allow(dead_code)]
extern "C" {
    static storage_start: u8;
    static storage_end: u8;
    static storage_size: u8;
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    let mut flash = Nvmc::new(p.NVMC);

    let storage_offset = core::ptr::addr_of!(storage_start) as u32;
    info!("Storage offset is: 0x{:08X}", storage_offset);
    let size = core::ptr::addr_of!(storage_size) as usize;
    info!("Size is: {}", size);

    let mut read_buf = [0u8; 16];
    info!("Initial reading {} bytes from storage...", read_buf.len());
    flash.read(storage_offset, &mut read_buf).unwrap();
    info!("Read done: {:02x}", read_buf);

    info!("Erasing storage region at 0x{:08X}...", storage_offset);
    flash
        .erase(storage_offset, storage_offset + size as u32)
        .unwrap();
    info!("Erase done.");

    let data_to_write: [u8; 16] = [
        0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0xEF,
        0xBE,
    ];
    info!("Writing {} bytes to storage...", data_to_write.len());
    flash.write(storage_offset, &data_to_write).unwrap();
    info!("Write done.");

    let mut read_buf = [0u8; 16];
    info!("Reading {} bytes from storage...", read_buf.len());
    flash.read(storage_offset, &mut read_buf).unwrap();
    info!("Read done: {:02x}", read_buf);

    assert_eq!(&read_buf, &data_to_write, "Data mismatch!");
    info!("Data verified successfully!");

    let data2: [u8; 16] = [
        0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08,
    ];
    info!("Erasing and rewriting...");
    flash
        .erase(storage_offset, storage_offset + size as u32)
        .unwrap();
    flash.write(storage_offset, &data2).unwrap();
    flash.read(storage_offset, &mut read_buf).unwrap();
    assert_eq!(&read_buf, &data2, "Second data mismatch!");
    info!("Second write verified: {:02x}", read_buf);

    info!("ALL DONE - flash test passed!");

    loop {
        embassy_time::Timer::after(embassy_time::Duration::from_secs(1)).await;
    }
}
