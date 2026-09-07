//! pump-controller 1.8 - infusion rate control and occlusion alarms.
pub fn set_rate(ml_per_h: u32) { serial::send(Cmd::Rate(ml_per_h)) }
