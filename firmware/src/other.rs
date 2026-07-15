use crate::prelude::*;

pub trait Nrcrap<T, E> {
    async fn nrcrap(self) -> T;
}

impl<T, E> Nrcrap<T, E> for Result<T, E>
where
    E: Format,
{
    async fn nrcrap(self) -> T {
        match self {
            Ok(val) => val,
            Err(e) => {
                #[cfg(feature = "debug")]
                {
                    let loc = core::panic::Location::caller();
                    error!("Ncrap failed at {}: {:?}", loc, e);
                }
                if crate::config::BLINK_ON_PROBLEM {
                    for _ in 0..3 {
                        let _ = LED_CHANNEL.try_send(LedCommand::Blink);
                        Timer::after(Duration::from_millis(200)).await;
                    }
                    Timer::after(Duration::from_secs(1)).await;
                }
                #[cfg(feature = "debug")]
                panic!("nrcrap failed at {}", core::panic::Location::caller());
                #[cfg(not(feature = "debug"))]
                panic!("nrcrap failed");
            }
        }
    }
}

impl<T> Nrcrap<T, ()> for Option<T> {
    async fn nrcrap(self) -> T {
        match self {
            Some(val) => val,
            None => {
                #[cfg(feature = "debug")]
                {
                    let loc = core::panic::Location::caller();
                    error!("Ncrap failed at {}: None", loc);
                }
                if crate::config::BLINK_ON_PROBLEM {
                    for _ in 0..3 {
                        let _ = LED_CHANNEL.try_send(LedCommand::Blink);
                        Timer::after(Duration::from_millis(200)).await;
                    }
                    Timer::after(Duration::from_secs(1)).await;
                }
                #[cfg(feature = "debug")]
                panic!("nrcrap failed at {}", core::panic::Location::caller());
                #[cfg(not(feature = "debug"))]
                panic!("nrcrap failed");
            }
        }
    }
}

pub trait Log<T> {
    fn log(&self);
}

impl<T, E> Log<T> for Result<T, E>
where
    E: Format,
{
    fn log(&self) {
        if let Err(e) = self {
            error!("{:?}", e);
        }
    }
    /*
    fn log_ms(self, msg: &str) {
        if let Err(e) = self {
            error!("{}: {:?}", msg, e);
        }
    }
    */
}
