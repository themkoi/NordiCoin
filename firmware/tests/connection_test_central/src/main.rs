#![no_std]
#![no_main]

use core::cell::RefCell;

use bt_hci::param::{AddrKind, BdAddr, FilterDuplicates, LeAdvReportsIter};
use defmt::info;
use defmt::unwrap;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_futures::select::select;
use embassy_nrf::mode::Async;
use embassy_nrf::peripherals::RNG;
use embassy_nrf::{bind_interrupts, rng};
use embassy_time::{Duration, Timer};
use heapless::Deque;
use nrf_sdc::mpsl::MultiprotocolServiceLayer;
use nrf_sdc::{self as sdc, mpsl};
use static_cell::StaticCell;
use trouble_host::prelude::*;
use {defmt_rtt as _, panic_probe as _};

const TARGET_ADDRESS: [u8; 6] = [206, 23, 126, 69, 54, 87];

const BATTERY_SERVICE_UUID: Uuid = Uuid::new_short(0x180f);
const BATTERY_LEVEL_UUID: Uuid = Uuid::new_short(0x2a19);

const LOW_POWER_CONN_PARAMS: RequestedConnParams = RequestedConnParams {
    min_connection_interval: Duration::from_secs(4),
    max_connection_interval: Duration::from_secs(4),
    max_latency: 0,
    supervision_timeout: Duration::from_secs(10),
    min_event_length: Duration::from_millis(0),
    max_event_length: Duration::from_millis(0),
};

const SCAN_INTERVAL_MS: u64 = 3000;
const SCAN_WINDOW_MS: u64 = 300;
const SLEEP_BETWEEN_SCANS_MS: u64 = 1000;
const CYCLE_INTERVAL: Duration = Duration::from_secs(2);
const MAX_DEVICES: usize = 16;

const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 3;

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
        .support_scan()
        .support_ext_scan()
        .support_central()
        .support_ext_central()
        .central_count(1)?
        .build(p, rng, mpsl, mem)
}

#[derive(Debug, Copy, Clone)]
struct DiscoveredDevice {
    kind: AddrKind,
    addr: BdAddr,
    rssi: i8,
}

struct DeviceList {
    devices: RefCell<Deque<DiscoveredDevice, MAX_DEVICES>>,
}

impl DeviceList {
    fn new() -> Self {
        Self {
            devices: RefCell::new(Deque::new()),
        }
    }

    fn add(&self, kind: AddrKind, addr: BdAddr, rssi: i8) {
        let mut devices = self.devices.borrow_mut();
        let mut found = false;
        let mut i = 0;
        while i < devices.len() {
            let dev = devices.get(i).unwrap();
            if dev.addr.raw() == addr.raw() {
                devices.get_mut(i).unwrap().rssi = rssi;
                found = true;
                break;
            }
            i += 1;
        }
        if !found {
            if devices.is_full() {
                devices.pop_front();
            }
            devices
                .push_back(DiscoveredDevice { kind, addr, rssi })
                .unwrap();
        }
    }

    fn len(&self) -> usize {
        self.devices.borrow().len()
    }

    fn get(&self, index: usize) -> Option<DiscoveredDevice> {
        self.devices.borrow().get(index).copied()
    }
}

impl EventHandler for DeviceList {
    fn on_adv_reports(&self, mut it: LeAdvReportsIter<'_>) {
        while let Some(Ok(report)) = it.next() {
            info!("Adding device {:?}", report.addr);
            self.add(report.addr_kind, report.addr, report.rssi);
        }
    }
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    info!("Nordicoin BLE Central test");
    info!("It does not work!");

    let mpsl_p =
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
    let mut sdc_mem = sdc::Mem::<3224>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    Timer::after(Duration::from_millis(200)).await;

    let address: Address = Address::random([0xff, 0x8f, 0x1b, 0x05, 0xe4, 0xff]);
    let mut resources: HostResources<_, DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();

    let target: Address = Address::random(TARGET_ADDRESS);
    info!("Target address: {:?}", target);

    let central = stack.central();
    let mut scanner = Scanner::new(central);
    let mut runner = stack.runner();

    let mut scan_config = ScanConfig::default();
    scan_config.active = false;
    scan_config.phys = PhySet::M1;
    scan_config.interval = Duration::from_millis(SCAN_INTERVAL_MS);
    scan_config.window = Duration::from_millis(SCAN_WINDOW_MS);

    scan_config.filter_duplicates = FilterDuplicates::Enabled;

    info!(
        "Starting low-power passive scan (interval={}ms, window={}ms, sleep={}ms)",
        SCAN_INTERVAL_MS, SCAN_WINDOW_MS, SLEEP_BETWEEN_SCANS_MS
    );

    loop {
        info!(">>> Scanning for BLE devices (duty-cycled passive scan)...");
        let device_list = DeviceList::new();

        let _ = select(
            join(runner.run_with_handler(&device_list), async {
                loop {
                    match scanner.scan(&scan_config).await {
                        Ok(_session) => {
                            Timer::after(Duration::from_millis(SLEEP_BETWEEN_SCANS_MS)).await;
                        }
                        Err(e) => {
                            defmt::error!("Scan error: {:?}", e);
                            Timer::after(Duration::from_millis(SLEEP_BETWEEN_SCANS_MS)).await;
                        }
                    }
                }
            }),
            async {
                Timer::after(Duration::from_secs(10)).await;
            },
        )
        .await;

        let count = device_list.len();
        info!(
            ">>> Scan complete. Found {} device(s), looking for target {:?}",
            count, target
        );

        if count == 0 {
            info!("No devices found. Retrying in {:?}...", CYCLE_INTERVAL);
            Timer::after(CYCLE_INTERVAL).await;
            continue;
        }

        for i in 0..count {
            if let Some(dev) = device_list.get(i) {
                info!("Device: {:?}", defmt::Debug2Format(&dev));
            }
        }

        let mut matched: Option<(DiscoveredDevice, Address)> = None;
        for i in 0..count {
            if let Some(dev) = device_list.get(i) {
                let dev_addr = Address::new(dev.kind, dev.addr);
                if dev_addr == target {
                    info!("*** Target address matched! RSSI: {} dBm ***", dev.rssi);
                    matched = Some((dev, dev_addr));
                    break;
                }
            }
        }

        let Some((chosen, chosen_addr)) = matched else {
            info!(
                "Target {:?} not found in scan results. Retrying in {:?}...",
                target, CYCLE_INTERVAL
            );
            Timer::after(CYCLE_INTERVAL).await;
            continue;
        };
        info!(
            ">>> Connecting to target: {:?} (RSSI: {} dBm)",
            chosen_addr, chosen.rssi
        );

        let config = ConnectConfig {
            connect_params: LOW_POWER_CONN_PARAMS,
            scan_config: ScanConfig {
                active: true,
                filter_accept_list: &[chosen_addr],
                phys: PhySet::M1M2Coded,
                ..Default::default()
            },
        };

        info!("[1/4] Connecting...");
        let conn = match stack.central().connect(&config).await {
            Ok(c) => c,
            Err(e) => {
                info!("[1/4] Connect failed: {:?}", e);
                Timer::after(CYCLE_INTERVAL).await;
                continue;
            }
        };
        info!("[1/4] Connected!");

        info!("[2/4] Setting up GATT client...");
        let client = match GattClient::<_, DefaultPacketPool, 10>::new(&stack, &conn).await {
            Ok(c) => c,
            Err(e) => {
                info!("[2/4] GATT client failed: {:?}", e);
                conn.disconnect();
                Timer::after(CYCLE_INTERVAL).await;
                continue;
            }
        };

        info!("[3/4] Reading battery level...");
        match read_battery_level(&client).await {
            Ok(level) => {
                info!("[3/4] Battery level: {}%", level);
            }
            Err(e) => {
                info!("[3/4] Read failed: {:?}", e);
            }
        }

        info!("[4/4] Disconnecting...");
        conn.disconnect();

        info!("Cycle complete. Sleeping {}s...", CYCLE_INTERVAL.as_secs());
        Timer::after(CYCLE_INTERVAL).await;
    }
}

async fn read_battery_level<'a, C: Controller, P: PacketPool, const N: usize>(
    client: &GattClient<'a, C, P, N>,
) -> Result<u8, BleHostError<C::Error>> {
    let services = client.services_by_uuid(&BATTERY_SERVICE_UUID).await?;
    let service = services.first().ok_or(Error::NotFound)?;

    let char: Characteristic<u8> = client
        .characteristic_by_uuid(&service, &BATTERY_LEVEL_UUID)
        .await?;

    let mut data = [0u8; 1];
    client.read_characteristic(&char, &mut data).await?;
    Ok(data[0])
}
