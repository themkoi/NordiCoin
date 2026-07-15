use crate::ble::{advertise::advertise, gatt::gatt_manager};
pub use crate::prelude::*;
use bt_hci::uuid::{appearance, BluetoothUuid16};
use embassy_nrf::{mode::Async, rng};
use embassy_time::Instant;
use nrf_mpsl::MultiprotocolServiceLayer;

mod advertise;
mod gatt;

#[embassy_executor::task]
pub async fn mpsl_task(mpsl: &'static MultiprotocolServiceLayer<'static>) -> ! {
    mpsl.run().await
}

// How many outgoing L2CAP buffers per link
const L2CAP_TXQ: u8 = 3;
// How many incoming L2CAP buffers per link
const L2CAP_RXQ: u8 = 3;
const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 2;

pub fn build_sdc<'d, const N: usize>(
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
        .buffer_cfg(
            DefaultPacketPool::MTU as u16,
            DefaultPacketPool::MTU as u16,
            L2CAP_TXQ,
            L2CAP_RXQ,
        )?
        .build(p, rng, mpsl, mem)
}

const NORDCOIN_SERVICE_UUID: BluetoothUuid16 = BluetoothUuid16::new(0x0001);
const FIND_ME_LOUD_CHAR: BluetoothUuid16 = BluetoothUuid16::new(0x0002); // in seconds
const FIND_ME_QUIET_CHAR: BluetoothUuid16 = BluetoothUuid16::new(0x0003); // in seconds
const UPTIME_CHAR: BluetoothUuid16 = BluetoothUuid16::new(0x0004); // in minutes
const TX_POWER_CHAR: BluetoothUuid16 = BluetoothUuid16::new(0x0005);
const BONDED_CHAR: BluetoothUuid16 = BluetoothUuid16::new(0x0006);

#[gatt_server]
struct Server {
    service: NordCoinService,
}

#[gatt_service(uuid = NORDCOIN_SERVICE_UUID)]
struct NordCoinService {
    #[characteristic(uuid = FIND_ME_LOUD_CHAR, write)]
    find_me_loud: u8,
    #[characteristic(uuid = FIND_ME_QUIET_CHAR, write)]
    find_me_quiet: u8,
    #[characteristic(uuid = UPTIME_CHAR, read)]
    uptime: u32,
    #[characteristic(uuid = TX_POWER_CHAR, write)]
    tx_power: i8, // type is trouble_host::advertise::TxPower
    #[characteristic(uuid = BONDED_CHAR, write)]
    bonded: bool,
}

#[embassy_executor::task]
pub async fn ble_task(
    sdc: SoftdeviceController<'static>,
    mut adc: AdcReader,
    flash: &'static crate::peripherals::flash::FlashStorage,
) -> ! {
    let addr = read_device_address();
    info!(
        "MAC: {:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
        addr[0], addr[1], addr[2], addr[3], addr[4], addr[5]
    );
    let address: Address = Address::random(addr);

    let mut resources: HostResources<_, DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();

    let mut runner = stack.runner();
    let mut peripheral = stack.peripheral();

    let mut flash_data = flash.read().await;
    loop {
        let server = Server::new_with_config(GapConfig::Peripheral(PeripheralConfig {
            name: "",
            appearance: &appearance::UNKNOWN,
        }))
        .unwrap();

        #[allow(unused_must_use)] // Rust analyzer is screaming
        let res = select(runner.run(), async {
            loop {
                match advertise(&flash_data, address, &mut adc, &mut peripheral, &server).await {
                    Ok(conn) => {
                        let timeout = match flash_data.bonded {
                            true => BLE_CONN_TIMEOUT_BONDED,
                            false => BLE_CONN_TIMEOUT_NOT_BONDED,
                        };

                        // Set the uptime value
                        server
                            .set(
                                &server.service.uptime,
                                &((Instant::now().as_secs() / 60) as u32),
                            )
                            .log();

                        if BLINK_ON_CONNECTION {
                            LED_CHANNEL.send(LedCommand::TurnOnFor(timeout.as_secs() as u8)).await;
                        }

                        match select(
                            Timer::after(timeout),
                            gatt_manager(&mut flash_data, flash, &server, &conn, &stack),
                        )
                        .await
                        {
                            embassy_futures::select::Either::First(_) => {
                                warn!("Connection was too long!");
                            }
                            embassy_futures::select::Either::Second(_) => {
                                info!("Ending connection");
                            }
                        }
                    }
                    Err(e) => {
                        error!("Advertising error: {:?}", e);
                        Timer::after(Duration::from_secs(1)).await;
                    }
                    #[allow(unused)] // Rust analyzer is screaming
                    _ => {}
                }
            }
        })
        .await;

        match res {
            embassy_futures::select::Either::First(e) => {
                error!("BLE loop exited because runner exited: {:?}", e);
            }
            embassy_futures::select::Either::Second(_) => {
                info!("BLE loop exited, probably to apply name change");
            }
        }
    }
}
