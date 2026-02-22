///|
extern "c" fn c_fopen(path : Bytes, mode : Bytes) -> Int64 = "fopen"

///|
extern "c" fn c_fclose(fp : Int64) -> Int = "fclose"

///|
extern "c" fn c_fread(buf : Bytes, size : Int, count : Int, fp : Int64) -> Int = "fread"

///|
extern "c" fn c_fseek(fp : Int64, offset : Int64, whence : Int) -> Int = "fseek"

///|
extern "c" fn c_ftell(fp : Int64) -> Int64 = "ftell"

///|
let seek_set : Int = 0

///|
let seek_end : Int = 2

///|
fn to_c_string(text : String) -> Bytes {
  let encoded = @utf8.encode(text[:])
  let buf = @buffer.new(size_hint=encoded.length() + 1)
  buf.write_bytes(encoded)
  buf.write_byte(0)
  buf.to_bytes()
}

///|
fn read_file_bytes(path : String) -> Bytes? {
  let fp = c_fopen(to_c_string(path), to_c_string("rb"))
  if fp == 0 {
    return None
  }
  // Get file size
  if c_fseek(fp, 0L, seek_end) != 0 {
    let _ = c_fclose(fp)
    return None
  }
  let size = c_ftell(fp).to_int()
  if size < 0 {
    let _ = c_fclose(fp)
    return None
  }
  if c_fseek(fp, 0L, seek_set) != 0 {
    let _ = c_fclose(fp)
    return None
  }
  // Read file content
  let buf = Bytes::new(size)
  let read_count = c_fread(buf, 1, size, fp)
  let _ = c_fclose(fp)
  if read_count != size {
    return None
  }
  Some(buf)
}

///|
pub fn load_dic_from_path(dicdir : String) -> (Bool, String) {
  // Strategy:
  // 1. Try micado dic.bin format first (full, medium, mini, tiny)
  // 2. Fall back to MeCab format (sys.dic + matrix.bin)

  // Try micado dic.bin format (uncompressed only for native target)
  // Note: .dic.bin.deflate files are not supported on native target
  // because zlib FFI is not yet implemented. Use uncompressed .dic.bin files.
  let profiles = ["full", "medium", "mini", "tiny"]
  for profile in profiles {
    let bin_path = "\{dicdir}/\{profile}.dic.bin"
    match read_file_bytes(bin_path) {
      Some(bytes) => {
        let ok = @runtime.load_dic_bin(bytes[:])
        if ok {
          return (true, "loaded \{profile}.dic.bin from \{dicdir}")
        }
        return (false, "failed to parse \{profile}.dic.bin from \{dicdir}")
      }
      None => ()
    }
  }

  // Try single dic.bin file
  let single_path = "\{dicdir}/dic.bin"
  match read_file_bytes(single_path) {
    Some(bytes) => {
      let ok = @runtime.load_dic_bin(bytes[:])
      if ok {
        return (true, "loaded dic.bin from \{dicdir}")
      }
      return (false, "failed to parse dic.bin from \{dicdir}")
    }
    None => ()
  }

  // Check for MeCab binary format (sys.dic + matrix.bin)
  // We no longer support loading these directly - suggest conversion instead
  let sys_dic_path = "\{dicdir}/sys.dic"
  match read_file_bytes(sys_dic_path) {
    Some(_) => {
      return (
        false,
        "MeCab binary format detected (sys.dic). Please convert to micado format first:\n  node tools/dict-compiler/scripts/convert_mecab.mjs \{dicdir} -o OUTPUT.dic.bin",
      )
    }
    None => ()
  }

  (false, "no dictionary found in \{dicdir} (tried *.dic.bin)")
}

///|
pub fn is_native_io_available() -> Bool {
  true
}
