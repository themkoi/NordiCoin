use crate::prelude::*;

pub trait Log<T> {
    fn log(&self);
    fn log_ms(self, msg: &str); // log message
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
    fn log_ms(self, msg: &str) {
        if let Err(e) = self {
            error!("{}: {:?}", msg, e);
        }
    }
}
