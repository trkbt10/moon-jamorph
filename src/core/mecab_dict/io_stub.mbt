///|
pub fn load_dic_from_path(_dicdir : String) -> (Bool, String) {
  // In WASM mode, file system access is not available.
  // The dictionary must be loaded via the buffer API (push_dic_input_byte / load_dic_bin).
  (
    false,
    "file system access is not available in WASM mode; use the buffer API to load dictionaries",
  )
}

///|
pub fn is_native_io_available() -> Bool {
  false
}
