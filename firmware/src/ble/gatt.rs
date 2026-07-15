use crate::{ble::Server, prelude::*};
use trouble_host::types::gatt_traits::FromGatt;

pub async fn gatt_manager<C: Controller, P: PacketPool>(
    server: &Server<'_>,
    conn: &GattConnection<'_, '_, P>,
    stack: &Stack<'_, C, P>,
) -> Result<(), Error> {
    let find_me_loud_char = server.service.find_me_loud;
    let find_me_quiet_char = server.service.find_me_quiet;
    let _uptime_char = server.service.uptime;
    let tx_power_char = server.service.tx_power;
    let bonded_char = server.service.bonded;

    loop {
        match conn.next().await {
            GattConnectionEvent::Disconnected { reason } => {
                info!("Gatt disconnected: {:?}", reason);
                break;
            }
            GattConnectionEvent::PhyUpdated { tx_phy, rx_phy } => {
                info!("Gatt PHY updated: tx={:?}, rx={:?}", tx_phy, rx_phy);
            }
            GattConnectionEvent::ConnectionParamsUpdated {
                conn_interval,
                peripheral_latency,
                supervision_timeout,
            } => {
                info!(
                    "Gatt connection params updated: interval={:?}ms, latency={}, timeout={:?}ms",
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
                    "Gatt Data length updated: TX={}/{}us, RX={}/{}us",
                    max_tx_octets, max_tx_time, max_rx_octets, max_rx_time
                );
            }
            GattConnectionEvent::RequestConnectionParams(req) => {
                let params = req.params();
                info!(
                    "Gatt Central requests params: interval={:?}ms, latency={}",
                    params.min_connection_interval.as_millis(),
                    params.max_latency
                );

                if let Err(e) = req.accept(None, stack).await {
                    info!("Gatt Failed to accept connection params request: {:?}", e);
                }
            }
            GattConnectionEvent::Gatt { event } => {
                let reply = match event {
                    GattEvent::Read(event) => event.accept(),
                    GattEvent::Write(event) => {
                        let result: Result<(), AttErrorCode> = event.with_data(|offset, data| {
                            if offset != 0 {
                                return Err(AttErrorCode::INVALID_OFFSET);
                            }
                            let handle = event.handle();
                            if handle == find_me_loud_char.handle {
                                let value = u8::from_gatt(data)
                                    .map_err(|_| AttErrorCode::INVALID_ATTRIBUTE_VALUE_LENGTH)?;
                                info!("GATT Write: find_me_loud = {}", value);
                                PWM_CHANNEL.try_send(PwmCommand::TurnOnFor(value)).log();
                            } else if handle == find_me_quiet_char.handle {
                                let value = u8::from_gatt(data)
                                    .map_err(|_| AttErrorCode::INVALID_ATTRIBUTE_VALUE_LENGTH)?;
                                info!("GATT Write: find_me_quiet = {}", value);
                                LED_CHANNEL.try_send(LedCommand::TurnOnFor(value)).log();
                            } else if handle == tx_power_char.handle {
                                let value = u8::from_gatt(data)
                                    .map_err(|_| AttErrorCode::INVALID_ATTRIBUTE_VALUE_LENGTH)?;
                                info!("GATT Write: tx_power = {}", value);
                            } else if handle == bonded_char.handle {
                                let value = bool::from_gatt(data)
                                    .map_err(|_| AttErrorCode::INVALID_ATTRIBUTE_VALUE_LENGTH)?;
                                info!("GATT Write: bonded = {}", value);
                            }
                            Ok(())
                        });

                        match result {
                            Ok(()) => event.accept(),
                            Err(code) => {
                                error!("GATT Write rejected: {:?}", code);
                                event.reject(code)
                            }
                        }
                    }
                    _ => event.accept(),
                };
                match reply {
                    Ok(reply) => {
                        reply.send().await;
                    }
                    Err(e) => {
                        warn!("Gatt error sending response: {:?}", e);
                    }
                };
            }
            _ => {}
        }
    }
    Ok(())
}
