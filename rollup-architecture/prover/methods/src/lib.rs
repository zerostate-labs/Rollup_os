// Re-export the guest ELF and METHOD_ID
pub const ROLLUP_GUEST_ELF: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/rollup_guest"));
pub const ROLLUP_METHOD_ID: [u8; 32] = *include_bytes!(concat!(env!("OUT_DIR"), "/rollup_guest.id"));
