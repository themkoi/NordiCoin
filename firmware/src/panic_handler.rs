use core::panic::PanicInfo;

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    #[cfg(feature = "debug")]
    crate::error!("{}", info);

    cortex_m::interrupt::disable();

    // Probably won't work
    let mut delay_count: u32 = 0;
    let target: u32 = 8000000;
    while delay_count < target {
        cortex_m::asm::nop();
        delay_count += 1;
    }

    cortex_m::peripheral::SCB::sys_reset();
}
