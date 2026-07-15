fn nibble_to_hex(n: u8) -> u8 {
    match n {
        0..=9 => b'0' + n,
        _ => b'a' + n - 10,
    }
}

pub use crate::prelude::*;
use crate::{
    ble::Server,
    peripherals::flash::{tx_power_from_i8, FlashData},
};
use bt_hci::{
    cmd::le::{
        LeClearAdvSets, LeReadNumberOfSupportedAdvSets, LeSetAdvSetRandomAddr, LeSetExtAdvData,
        LeSetExtAdvEnable, LeSetExtAdvParams, LeSetExtScanResponseData,
    },
    controller::ControllerCmdSync,
};
use embassy_futures::select::Either::First;
pub async fn advertise<'values, 'server, C: Controller>(
    flash_data: &FlashData,
    address: Address,
    adc: &mut AdcReader,
    peripheral: &mut Peripheral<'values, C, DefaultPacketPool>,
    server: &'server Server<'values>,
) -> Result<GattConnection<'values, 'server, DefaultPacketPool>, BleHostError<C::Error>>
where
    C: ControllerCmdSync<LeClearAdvSets>
        + ControllerCmdSync<LeSetExtAdvParams>
        + ControllerCmdSync<LeSetAdvSetRandomAddr>
        + ControllerCmdSync<LeReadNumberOfSupportedAdvSets>
        + for<'t> ControllerCmdSync<LeSetExtAdvData<'t>>
        + for<'t> ControllerCmdSync<LeSetExtAdvEnable<'t>>
        + for<'t> ControllerCmdSync<LeSetExtScanResponseData<'t>>,
{
    let mut adv_data = [0u8; 31];
    loop {
        let out = select(
            async {
                let bat_byte = adc.get_bat_byte().await;
                info!("Bonded status: {}", flash_data.bonded);
                let len = match flash_data.bonded {
                    true => {
                        let len = AdStructure::encode_slice(
                            &[
                                AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
                                // Otherwise it doesn't work, because we don't follow ble spec
                                AdStructure::Unknown {
                                    ty: 0x21,
                                    data: &[bat_byte],
                                },
                            ],
                            &mut adv_data[..],
                        )
                        .nrcrap().await;
                        /*
                         info!("Adv data before bat byte: {:?}", adv_data[..len]);
                         adv_data[len] = bat_byte;
                         len += 1;
                         info!("Adv data after bat byte: {:?}", adv_data[..len]);
                        */
                        len
                    }
                    false => {
                        let device_id = read_device_id();
                        // DEVICE_ID_LENGTH * 2 because each byte of the device ID is encoded as 2 hex characters
                        let mut buf = [0u8; BLE_NAME_NOT_BONDED.len() + DEVICE_ID_LENGTH * 2];
                        buf[..BLE_NAME_NOT_BONDED.len()]
                            .copy_from_slice(BLE_NAME_NOT_BONDED.as_bytes());
                        let hex = &mut buf[BLE_NAME_NOT_BONDED.len()..];
                        let mut i = 0;
                        for byte in device_id.to_be_bytes().iter() {
                            hex[i] = nibble_to_hex(byte >> 4);
                            hex[i + 1] = nibble_to_hex(byte & 0x0F);
                            i += 2;
                        }
                        let hex_len = DEVICE_ID_LENGTH * 2;
                        info!(
                            "Final not bonded device name is: {:?}",
                            Debug2Format(&str::from_utf8(&buf))
                        );

                        AdStructure::encode_slice(
                            &[
                                AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
                                AdStructure::CompleteLocalName(
                                    &buf[..BLE_NAME_NOT_BONDED.len() + hex_len],
                                ),
                            ],
                            &mut adv_data[..],
                        )
                        .nrcrap().await
                    }
                };

                const INTERVAL_MIN_MS: u64 = 5000;
                const INTERVAL_MAX_MS: u64 = 5100;

                let adv_params = AdvertisementParameters {
                    primary_phy: Default::default(),
                    secondary_phy: Default::default(),
                    tx_power: tx_power_from_i8(flash_data.tx_power),
                    timeout: None,
                    max_events: None,
                    interval_min: Duration::from_millis(INTERVAL_MIN_MS),
                    interval_max: Duration::from_millis(INTERVAL_MAX_MS),
                    filter_policy: AdvFilterPolicy::default(),
                    channel_map: None, // Can't be changed
                    fragment: false,
                    own_addr_kind: None,
                };

                let sets = [AdvertisementSet {
                    params: adv_params,
                    address: Some(address.addr),
                    // It's possible to choose better modes, but that would conflict, because I want many devices to see it properly
                    // Maybe it's possible to do that, but the problem is the data length which increases power consumption
                    data: Advertisement::ExtConnectableNonscannableUndirected {
                        adv_data: &adv_data[..len],
                    },
                }; 1];
                let mut handles = [AdvSet {
                    adv_handle: bt_hci::param::AdvHandle::new(0),
                    // So nothing, but from_u16 contains no logic
                    duration: bt_hci::param::Duration::from_u16(0),
                    max_ext_adv_events: 0,
                }; 1];

                let advertiser = peripheral.advertise_ext(&sets, &mut handles).await?;
                info!("Advertising");

                let conn = advertiser.accept().await?.with_attribute_server(server)?;
                info!("Connection established");
                return Ok::<_, BleHostError<C::Error>>(conn);
            },
            async {
                Timer::after(BLE_REFRESH_BATTERY).await;
                info!("BLE_REFRESH_BATTERY passed, restarting advertising with fresh adc");
            },
        )
        .await;
        if let First(f) = out {
            return f;
        }
    }
}
