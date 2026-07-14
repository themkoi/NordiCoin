use crate::prelude::*;

pub fn read_device_address() -> [u8; 6] {
    // This shouldn't change?
    assert_eq!(read_device_address_type(), 1);
    
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

pub const DEVICE_ID_LENGTH: usize = 4;
pub fn read_device_id() -> u32 {
    let id_0 = pac::FICR.deviceid(0).read();
    let id_1 = pac::FICR.deviceid(1).read();

    let first_two = (id_0 >> 16) as u16;

    let last_two = id_1 as u16;

    ((first_two as u32) << 16) | (last_two as u32)
}
