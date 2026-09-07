//! left-pad 1.0 - pulled in by the touchscreen UI.
pub fn left_pad(s: &str, n: usize) -> String { format!("{s:>n$}") }
