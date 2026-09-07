//! audit-log-exporter 1.0 - optional module, ships the event log off-device.
pub fn export(events: &[Event]) -> Result<(), Error> { sink::write(events) }
