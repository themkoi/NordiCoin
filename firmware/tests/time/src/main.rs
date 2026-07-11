#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use {defmt_rtt as _, panic_probe as _};

const BASE_UNIX_TIME: u64 = 1_700_000_000;

fn days_to_date(days: u64) -> (u64, u64, u64) {
    let mut rem = days;
    let mut year: u64 = 1970;
    loop {
        let diy = if is_leap(year) { 366 } else { 365 };
        if rem < diy { break; }
        rem -= diy;
        year += 1;
    }
    let mut md = [31u8; 12];
    if is_leap(year) { md[1] = 29; }
    let mut month: u64 = 1;
    for &m in &md {
        if rem < m as u64 { break; }
        rem -= m as u64;
        month += 1;
    }
    (year, month, rem + 1)
}

fn is_leap(y: u64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let config = embassy_nrf::config::Config::default();
    let _p = embassy_nrf::init(config);

    loop {
        let elapsed_secs = embassy_time::Instant::now().as_secs();
        let unix_time = BASE_UNIX_TIME + elapsed_secs;

        let (dy, dm, dd) = days_to_date(unix_time / 86_400);
        let rem = unix_time % 86_400;
        let h = rem / 3_600;
        let m = (rem % 3_600) / 60;
        let s = rem % 60;

        info!(
            "Unix time: {} ({:04}-{:02}-{:02} {:02}:{:02}:{:02}) [elapsed={}s]",
            unix_time, dy, dm, dd, h, m, s, elapsed_secs
        );

        Timer::after(Duration::from_secs(5)).await;
    }
}
