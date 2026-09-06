use crate::prelude::*;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::channel::Channel;
use embassy_futures::join::join;
use embassy_nrf::mode::Async;
use embassy_nrf::rng;
use embassy_time::{Duration, Timer};
use core::sync::atomic::{AtomicU8, Ordering};
use nrf_mpsl::MultiprotocolServiceLayer;
use trouble_host::prelude::*;

/// Max number of connections (set to 0 for pure advertising).
const CONNECTIONS_MAX: usize = 0;

/// Max number of L2CAP channels (set to 0 for pure advertising).
const L2CAP_CHANNELS_MAX: usize = 0;

/// Global channel to pass the button action type (0x0 or 0x1) to the BLE task.
pub static BLE_CHANNEL: Channel<CriticalSectionRawMutex, u8, 4> = Channel::new();

/// Build the Nordic SoftDevice Controller configured for legacy advertising.
pub fn build_sdc<'d, const N: usize>(
    p: nrf_sdc::Peripherals<'d>,
    rng: &'d mut rng::Rng<Async>,
    mpsl: &'d MultiprotocolServiceLayer<'d>,
    mem: &'d mut nrf_sdc::Mem<N>,
) -> Result<nrf_sdc::SoftdeviceController<'d>, nrf_sdc::Error> {
    nrf_sdc::Builder::new()?
        .support_adv()
        .build(p, rng, mpsl, mem)
}

#[embassy_executor::task]
pub async fn run_ble_task(controller: SoftdeviceController<'static>) {
    let mut resources: HostResources<
        SoftdeviceController<'static>,
        DefaultPacketPool,
        CONNECTIONS_MAX,
        L2CAP_CHANNELS_MAX,
    > = HostResources::new();

    let addr = read_device_address();

    info!(
        "Device address: {:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
        addr[5], addr[4], addr[3], addr[2], addr[1], addr[0]
    );

    let address = Address::random(addr);

    let stack = trouble_host::new(controller, &mut resources)
        .set_random_address(address)
        .build();

    let mut runner = stack.runner();
    let mut peripheral = stack.peripheral();

    static COUNTER: AtomicU8 = AtomicU8::new(0);

    let _ = join(
        async {
            loop {
                if let Err(e) = runner.run().await {
                    info!("BLE runner error: {:?}", e);
                }
            }
        },
        async {
            loop {
                let action_type = BLE_CHANNEL.receive().await;
                let count = COUNTER.fetch_add(1, Ordering::Relaxed);
                
                let payload = [action_type, count];

                info!("Starting legacy advertising with action: {:02x}, counter: {}...", action_type, count);

                let mut adv_buf = [0u8; 31];
                let len = AdStructure::encode_slice(
                    &[
                        AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
                        AdStructure::Unknown {
                            ty: 0x21,
                            data: &payload,
                        },
                    ],
                    &mut adv_buf,
                )
                .unwrap();

                let mut params = AdvertisementParameters::default();
                params.interval_min = Duration::from_millis(20);
                params.interval_max = Duration::from_millis(20);

                let advertiser = match peripheral
                    .advertise(
                        &params,
                        Advertisement::NonconnectableScannableUndirected {
                            adv_data: &adv_buf[..len],
                            scan_data: &[],
                        },
                    )
                    .await
                {
                    Ok(adv) => adv,
                    Err(e) => {
                        info!("Advertising error: {:?}", e);
                        continue;
                    }
                };

                info!("Advertising active. Waiting for 200 milis...");
                
                let _ = embassy_futures::select::select(
                    advertiser.accept(),
                    Timer::after(Duration::from_millis(200)),
                )
                .await;

                info!("Advertising session finished. Clearing pending channel clicks.");
                
                BLE_CHANNEL.clear();
            }
        },
    )
    .await;
}