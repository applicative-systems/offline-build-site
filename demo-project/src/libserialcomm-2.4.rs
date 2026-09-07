//! libserialcomm 2.4 - RS-232 transport for the syringe driver bus.
pub fn open(port: &str) -> Port { Port::claim(port, Baud::B9600) }
