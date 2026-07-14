#![no_std]
#![no_main]

use bt_hci::cmd::le::{
    LeClearAdvSets, LeReadNumberOfSupportedAdvSets, LeSetAdvSetRandomAddr, LeSetExtAdvData,
    LeSetExtAdvEnable, LeSetExtAdvParams, LeSetExtScanResponseData,
};
use bt_hci::controller::ControllerCmdSync;
use bt_hci::param::AdvSet;
use defmt::info;
use defmt::unwrap;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::RNG;
use embassy_nrf::{bind_interrupts, rng};
use embassy_time::{Duration, Timer};
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use static_cell::StaticCell;
use trouble_host::prelude::*;
use {defmt_rtt as _, panic_probe as _};

const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 2;

bind_interrupts!(struct Irqs {
    RNG => rng::InterruptHandler<RNG>;
    EGU0_SWI0 => nrf_sdc::mpsl::LowPrioInterruptHandler;
    CLOCK_POWER => nrf_sdc::mpsl::ClockInterruptHandler;
    RADIO => nrf_sdc::mpsl::HighPrioInterruptHandler;
    TIMER0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
    RTC0 => nrf_sdc::mpsl::HighPrioInterruptHandler;
});

#[embassy_executor::task]
async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

fn build_sdc<'d, const N: usize>(
    p: nrf_sdc::Peripherals<'d>,
    rng: &'d mut rng::Rng<Async>,
    mpsl: &'d MultiprotocolServiceLayer,
    mem: &'d mut sdc::Mem<N>,
) -> Result<nrf_sdc::SoftdeviceController<'d>, nrf_sdc::Error> {
    sdc::Builder::new()?
        .support_adv()
        .support_ext_adv()
        .support_peripheral()
        .peripheral_count(1)?
        .buffer_cfg(27, 27, 3, 3)?
        .build(p, rng, mpsl, mem)
}

const TEST_SERVICE_UUID: Uuid = Uuid::new_short(0x1800);

const STATUS_CHAR_UUID: Uuid = Uuid::new_short(0x2A00);

const DATA_CHAR_UUID: Uuid = Uuid::new_short(0x2A01);

#[gatt_server]
struct Server {
    test_service: TestService,
}

#[gatt_service(uuid = TEST_SERVICE_UUID)]
struct TestService {
    #[characteristic(uuid = STATUS_CHAR_UUID, read, notify, value = 12)]
    status: u16,

    #[characteristic(uuid = DATA_CHAR_UUID, read, write)]
    data: [u8; 20],
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    info!("Nordicoin BLE Peripheral - Connection Test");

    let mpsl_p: nrf_mpsl::Peripherals<'_> =
        mpsl::Peripherals::new(p.RTC0, p.TIMER0, p.TEMP, p.PPI_CH19, p.PPI_CH30, p.PPI_CH31);
    let lfclk_cfg = mpsl::raw::mpsl_clock_lfclk_cfg_t {
        source: mpsl::raw::MPSL_CLOCK_LF_SRC_RC as u8,
        rc_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_CTIV as u8,
        rc_temp_ctiv: mpsl::raw::MPSL_RECOMMENDED_RC_TEMP_CTIV as u8,
        accuracy_ppm: mpsl::raw::MPSL_DEFAULT_CLOCK_ACCURACY_PPM as u16,
        skip_wait_lfclk_started: mpsl::raw::MPSL_DEFAULT_SKIP_WAIT_LFCLK_STARTED != 0,
    };
    static MPSL: StaticCell<MultiprotocolServiceLayer> = StaticCell::new();
    let mpsl = MPSL.init(unwrap!(mpsl::MultiprotocolServiceLayer::new(
        mpsl_p, Irqs, lfclk_cfg
    )));
    spawner.spawn(unwrap!(mpsl_task(&*mpsl)));

    let sdc_p = sdc::Peripherals::new(
        p.PPI_CH17, p.PPI_CH18, p.PPI_CH20, p.PPI_CH21, p.PPI_CH22, p.PPI_CH23, p.PPI_CH24,
        p.PPI_CH25, p.PPI_CH26, p.PPI_CH27, p.PPI_CH28, p.PPI_CH29,
    );
    let mut rng = rng::Rng::new(p.RNG, Irqs);

    let mut sdc_mem = sdc::Mem::<4720>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    Timer::after(Duration::from_millis(200)).await;

    let address: Address = Address::random([0xff, 0x8f, 0x1b, 0x05, 0xe4, 0xff]);
    info!("Our address = {:?}", address);

    let mut resources: HostResources<_, DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();

    let runner = stack.runner();
    let mut peripheral = stack.peripheral();

    let server = Server::new_with_config(GapConfig::Peripheral(PeripheralConfig {
        name: "Nordicoin",
        appearance: &appearance::power_device::GENERIC_POWER_DEVICE,
    }))
    .unwrap();

    info!("Starting advertising with GATT service");

    let _ = join(ble_task(runner), async {
        loop {
            match advertise("Nordicoin", address, &mut peripheral, &server).await {
                Ok(conn) => {
                    gatt_events_task(&server, &conn, &stack).await.ok();
                }
                Err(e) => {
                    defmt::error!("[adv] error: {:?}", e);
                    Timer::after(Duration::from_secs(1)).await;
                }
            }
        }
    })
    .await;
}

async fn ble_task<C: Controller, P: PacketPool>(mut runner: Runner<'_, C, P>) {
    loop {
        if let Err(e) = runner.run().await {
            defmt::error!("[ble_task] error: {:?}", e);
        }
    }
}

async fn advertise<'values, 'server, C: Controller>(
    name: &'values str,
    address: Address,
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
    let mut advertiser_data = [0u8; 3];
    let len = AdStructure::encode_slice(
        &[
            AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
        ],
        &mut advertiser_data[..],
    )?;
    let _ = name;

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

/*
async fn optimize_connection_for_power<C: Controller, P: PacketPool>(
    conn: &GattConnection<'_, '_, P>,
    stack: &Stack<'_, C, P>,
) where
    C: ControllerCmdSync<LeSetDataLength>
        + ControllerCmdSync<LeReadLocalSupportedFeatures>
        + ControllerCmdAsync<LeSetPhy>
        + ControllerCmdAsync<LeConnUpdate>,
{
    /*
    info!("Waiting 2s to set conn parameters");
    Timer::after_secs(2).await;
    info!("Updating conn parameters");

    // These set defaults already, so no point in this
    const MAX_DATA_LENGTH: u16 = 251;
    const MAX_DATA_TIME: u16 = 2120;

    if let Err(e) = conn.raw().update_data_length(stack, MAX_DATA_LENGTH, MAX_DATA_TIME).await {
        info!("[power] data length update failed: {:?}", e);
    } else {
        info!("[power] data length optimized to {} octets", MAX_DATA_LENGTH);
    }

    if let Err(e) = conn.raw().set_phy(stack, PhyKind::Le1M).await {
        info!("[power] PHY update failed: {:?}", e);
    } else {
        info!("[power] PHY set to 1M");
    }
    */

    /*
    I get 37.248870 [INFO ] Connection parameters request procedure not supported, use l2cap connection parameter update req instead (trouble_host trouble-host-0.7.0/src/connection.rs:844)
    when trying, well, skip that
    */
    const POWER_EFFICIENT_CONN_PARAMS: RequestedConnParams = RequestedConnParams {
        min_connection_interval: Duration::from_millis(5000),
        max_connection_interval: Duration::from_millis(5000),
        max_latency: 9, // Skip up to 9 connection events
        min_event_length: Duration::from_secs(0),
        max_event_length: Duration::from_secs(0),
        supervision_timeout: Duration::from_secs(6),
    };
    if let Err(e) = conn
        .raw()
        .update_connection_params(stack, &POWER_EFFICIENT_CONN_PARAMS)
        .await
    {
        info!("[power] connection param update failed: {:?}", e);
    } else {
        info!("[power] connection params optimized");
    }
}
*/

async fn gatt_events_task<C: Controller, P: PacketPool>(
    server: &Server<'_>,
    conn: &GattConnection<'_, '_, P>,
    stack: &Stack<'_, C, P>,
) -> Result<(), Error> {
    let status_handle = server.test_service.status.handle;
    let data_handle = server.test_service.data.handle;
    let mut data = [0u8; 20];

    let _reason = loop {
        match conn.next().await {
            GattConnectionEvent::Disconnected { reason } => {
                info!("[gatt] disconnected: {:?}", reason);
                break reason;
            }
            GattConnectionEvent::PhyUpdated { tx_phy, rx_phy } => {
                info!("[gatt] PHY updated: tx={:?}, rx={:?}", tx_phy, rx_phy);
            }
            GattConnectionEvent::ConnectionParamsUpdated {
                conn_interval,
                peripheral_latency,
                supervision_timeout,
            } => {
                info!(
                    "[gatt] Connection params updated: interval={:?}ms, latency={}, timeout={:?}ms",
                    conn_interval.as_millis(),
                    peripheral_latency,
                    supervision_timeout.as_millis()
                );
            }
            GattConnectionEvent::DataLengthUpdated {
                max_tx_octets,
                max_tx_time,
                max_rx_octets,
                max_rx_time,
            } => {
                info!(
                    "[gatt] Data length updated: TX={}/{}us, RX={}/{}us",
                    max_tx_octets, max_tx_time, max_rx_octets, max_rx_time
                );
            }
            GattConnectionEvent::RequestConnectionParams(req) => {
                let params = req.params();
                info!(
                    "[gatt] Central requests params: interval={:?}ms, latency={}",
                    params.min_connection_interval.as_millis(),
                    params.max_latency
                );

                if let Err(e) = req.accept(None, stack).await {
                    info!("[gatt] Failed to accept connection params request: {:?}", e);
                }
            }
            GattConnectionEvent::Gatt { event } => {
                let reply = match event {
                    GattEvent::Read(event) => {
                        if event.handle() == status_handle {
                            let value = conn.get(&server.test_service.status);
                            info!("[gatt] Read request to status char: {:?}", value);
                            event.accept()
                        } else if event.handle() == data_handle {
                            info!("[gatt] Read request to data char: {:?}", data);
                            event.accept_unprocessed(&data)
                        } else {
                            event.accept()
                        }
                    }
                    GattEvent::Write(event) => {
                        if event.handle() == status_handle {
                            event.reject(AttErrorCode::WRITE_NOT_PERMITTED)
                        } else if event.handle() == data_handle {
                            match event.validate(0, 20) {
                                Ok(()) => {
                                    event.with_data(|offset, write_data| {
                                        info!(
                                            "[gatt] Write to data char at offset {}: {:?}",
                                            offset, write_data
                                        );
                                        let start = offset as usize;
                                        let end =
                                            (offset as usize + write_data.len()).min(data.len());
                                        if start < data.len() {
                                            data[start..end]
                                                .copy_from_slice(&write_data[..end - start]);
                                        }
                                    });
                                    event.accept()
                                }
                                Err(err) => {
                                    info!("[gatt] Write validation error: {:?}", err);
                                    event.reject(err)
                                }
                            }
                        } else {
                            event.accept()
                        }
                    }
                    _ => event.accept(),
                };
                match reply {
                    Ok(reply) => {
                        reply.send().await;
                    }
                    Err(e) => {
                        info!("[gatt] error sending response: {:?}", e);
                    }
                };
            }
            _ => {}
        }
    };
    Ok(())
}
