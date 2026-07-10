#![no_std]
#![no_main]

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
    sdc::Builder::new()?.support_adv().build(p, rng, mpsl, mem)
}

fn encode_adv_data<'a>(dest: &'a mut [u8]) -> &'a [u8] {
    let structures = [
        AdStructure::Flags(LE_GENERAL_DISCOVERABLE | BR_EDR_NOT_SUPPORTED),
        AdStructure::IncompleteServiceUuids16(&[[0x12, 0x18]]),
        AdStructure::CompleteLocalName(b"Nordicoin"),
        AdStructure::ManufacturerSpecificData {
            company_identifier: 0x0059,
            payload: &[0x01, 0x02, 0x03],
        },
    ];
    let len = AdStructure::encode_slice(&structures, dest).unwrap_or(0);
    &dest[..len]
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let mut config = embassy_nrf::config::Config::default();
    config.lfclk_source = embassy_nrf::config::LfclkSource::ExternalXtal;
    let p = embassy_nrf::init(config);

    Timer::after(Duration::from_millis(200)).await;

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

    let mut sdc_mem = sdc::Mem::<1152>::new();
    let sdc = unwrap!(build_sdc(sdc_p, &mut rng, mpsl, &mut sdc_mem));

    let address: Address = Address::random([0xff, 0x8f, 0x1b, 0x05, 0xe4, 0xff]);

    let mut resources: HostResources<_, DefaultPacketPool, 0, 0> = HostResources::new();
    let stack = trouble_host::new(sdc, &mut resources)
        .set_random_address(address)
        .build();

    let mut peripheral = stack.peripheral();
    let mut runner = stack.runner();

    let mut adv_buf = [0u8; 31];
    let adv_data = encode_adv_data(&mut adv_buf);

    const INTERVAL: u64 = 3000;
    let adv_params = AdvertisementParameters {
        primary_phy: Default::default(),
        secondary_phy: Default::default(),
        tx_power: TxPower::Minus40dBm,
        timeout: None,
        max_events: None,
        interval_min: Duration::from_millis(INTERVAL),
        interval_max: Duration::from_millis(INTERVAL),
        filter_policy: AdvFilterPolicy::default(),
        channel_map: None,
        fragment: false,
        own_addr_kind: None,
    };

    let adv = Advertisement::NonconnectableNonscannableUndirected { adv_data: adv_data };

    info!(
        "Starting beacon advertisement (interval={}ms)",
        adv_params.interval_min.as_millis()
    );

    let _ = join(runner.run(), async {
        loop {
            match peripheral.advertise(&adv_params, adv).await {
                Ok(_advertiser) => {
                    info!("Advertisement cycle complete");
                    Timer::after(Duration::from_secs(6)).await;
                }
                Err(e) => {
                    defmt::error!("Advertisement error: {:?}", e);
                    Timer::after(Duration::from_secs(1)).await;
                }
            }
        }
    })
    .await;
}
