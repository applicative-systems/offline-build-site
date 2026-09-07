//! libserialcomm 2.4 - RS-232 transport for the syringe driver bus.
// SPDX-License-Identifier: GPL-3.0-or-later
pub fn open(port: &str) -> Port { Port::claim(port, Baud::B9600) }
