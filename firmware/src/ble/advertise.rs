use crate::ble::Server;
pub use crate::prelude::*;
use bt_hci::{
    cmd::le::{
        LeClearAdvSets, LeReadNumberOfSupportedAdvSets, LeSetAdvSetRandomAddr, LeSetExtAdvData,
        LeSetExtAdvEnable, LeSetExtAdvParams, LeSetExtScanResponseData,
    },
    controller::ControllerCmdSync,
};

pub async fn advertise<'values, 'server, C: Controller>(
    name: &str,
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
    let mut advertiser_data = [0u8; 31];
    let len = AdStructure::encode_slice(
        &[
            AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
            AdStructure::CompleteLocalName(name.as_bytes()),
        ],
        &mut advertiser_data[..],
    )?;

    const INTERVAL_MIN_MS: u64 = 5000;
    const INTERVAL_MAX_MS: u64 = 5100;

    let adv_params = AdvertisementParameters {
        primary_phy: Default::default(),
        secondary_phy: Default::default(),
        tx_power: TxPower::Minus40dBm,
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
        data: Advertisement::ExtConnectableNonscannableUndirected {
            adv_data: &advertiser_data[..len],
        },
    }; 1];
    let mut handles = [AdvSet {
        adv_handle: bt_hci::param::AdvHandle::new(0),
        duration: bt_hci::param::Duration::from_u16(0),
        max_ext_adv_events: 0,
    }; 1];

    let advertiser = peripheral.advertise_ext(&sets, &mut handles).await?;
    info!("[adv] advertising");

    let conn = advertiser.accept().await?.with_attribute_server(server)?;
    info!("[adv] connection established");
    Ok(conn)
}

pub async fn get_ble_name() -> HeaplessString<BLE_NAME_LENGTH_MAX> {
    
    todo!();
}
