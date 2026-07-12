#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_nrf::pac;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

fn read_device_id() -> (u32, u32) {
    let id_0 = pac::FICR.deviceid(0).read();
    let id_1 = pac::FICR.deviceid(1).read();
    (id_0, id_1)
}

fn read_device_address() -> [u8; 6] {
    let lo = pac::FICR.deviceaddr(0).read();
    let hi = pac::FICR.deviceaddr(1).read();
    [
        (lo & 0xFF) as u8,
        ((lo >> 8) & 0xFF) as u8,
        ((lo >> 16) & 0xFF) as u8,
        ((lo >> 24) & 0xFF) as u8,
        (hi & 0xFF) as u8,
        ((hi >> 8) & 0xFF) as u8,
    ]
}

// Read the Device Address Type: 0 = Public, 1 = Random.
fn read_device_address_type() -> u8 {
    pac::FICR.deviceaddrtype().read().deviceaddrtype() as u8
}

fn read_part() -> u32 {
    u32::from(pac::FICR.info().part().read().part())
}

fn read_variant() -> u32 {
    u32::from(pac::FICR.info().variant().read().variant())
}

fn read_package() -> u32 {
    u32::from(pac::FICR.info().package().read().package())
}

fn read_ram() -> u32 {
    u32::from(pac::FICR.info().ram().read().ram())
}

fn read_flash() -> u32 {
    u32::from(pac::FICR.info().flash().read().flash())
}

fn read_code_memory() -> (u32, u32) {
    let page_size = pac::FICR.codepagesize().read();
    let count = pac::FICR.codesize().read();
    (page_size, count)
}

fn read_temp_calibration() -> ([u16; 5], [u16; 5], [u8; 5]) {
    let temp = pac::FICR.temp();
    let mut a = [0u16; 5];
    let mut b = [0u16; 5];
    let mut t = [0u8; 5];
    a[0] = temp.a0().read().a();
    b[0] = temp.b0().read().b();
    t[0] = temp.t0().read().t();
    a[1] = temp.a1().read().a();
    b[1] = temp.b1().read().b();
    t[1] = temp.t1().read().t();
    a[2] = temp.a2().read().a();
    b[2] = temp.b2().read().b();
    t[2] = temp.t2().read().t();
    a[3] = temp.a3().read().a();
    b[3] = temp.b3().read().b();
    t[3] = temp.t3().read().t();
    a[4] = temp.a4().read().a();
    b[4] = temp.b4().read().b();
    t[4] = temp.t4().read().t();
    (a, b, t)
}

fn read_encryption_root() -> [u32; 4] {
    let mut er = [0u32; 4];
    for i in 0..4 {
        er[i] = pac::FICR.er(i).read();
    }
    er
}

fn read_identity_root() -> [u32; 4] {
    let mut ir = [0u32; 4];
    for i in 0..4 {
        ir[i] = pac::FICR.ir(i).read();
    }
    ir
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let config = embassy_nrf::config::Config::default();
    let _p = embassy_nrf::init(config);

    info!("Device info test");

    let (id_0, id_1) = read_device_id();
    info!("Device ID = 0x{:016X}", ((id_1 as u64) << 32) | id_0 as u64);

    let addr = read_device_address();
    info!("Device Address (BLE MAC):");
    info!("MAC = {:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}", addr[0], addr[1], addr[2], addr[3], addr[4], addr[5]);
    info!("Raw = {:?}", addr);

    let addr_type = read_device_address_type();
    info!("Device Address Type: {}", if addr_type == 0 { "Public" } else { "Random" });

    info!("Part code: 0x{:08X}", read_part());
    info!("Variant: 0x{:08X}", read_variant());
    info!("Package: 0x{:08X}", read_package());
    info!("RAM: {} KB", read_ram());
    info!("Flash: {} KB", read_flash());

    let (page_size, page_count) = read_code_memory();
    info!("Code Page Size: {} bytes", page_size);
    info!("Code Size: {} pages ({} KB total)", page_count, page_count * page_size / 1024);

    let (a, b, t) = read_temp_calibration();
    info!("TEMP Calibration Coefficients:");
    for i in 0..5 {
        info!("A[{}] = {}, B[{}] = {}, T[{}] = {}", i, a[i], i, b[i], i, t[i]);
    }

    let er = read_encryption_root();
    info!("Encryption Root:");
    for i in 0..4 {
        info!("ER[{}] = 0x{:08X}", i, er[i]);
    }

    let ir = read_identity_root();
    info!("Identity Root:");
    for i in 0..4 {
        info!("IR[{}] = 0x{:08X}", i, ir[i]);
    }

    loop {
        Timer::after(Duration::from_secs(120)).await;
    }
}
