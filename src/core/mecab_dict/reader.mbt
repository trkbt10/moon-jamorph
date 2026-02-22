///|
/// Result type for dictionary loading operations
pub struct LoadResult {
  success : Bool
  message : String
}

///|
/// Creates a success result
pub fn LoadResult::ok(message : String) -> LoadResult {
  { success: true, message }
}

///|
/// Creates a failure result
pub fn LoadResult::error(message : String) -> LoadResult {
  { success: false, message }
}

///|
/// Load dictionary from a directory path.
/// On native targets, this reads files from the filesystem.
/// On WASM targets, this returns an error (use buffer API instead).
///
/// Supports both:
/// - micado dic.bin format (*.dic.bin, *.dic.bin.deflate)
/// - MeCab dictionary format (sys.dic + matrix.bin)
pub fn load_from_dicdir(dicdir : String) -> LoadResult {
  let (ok, msg) = load_dic_from_path(dicdir)
  { success: ok, message: msg }
}

///|
/// Load dictionary from raw bytes (works on all targets).
/// This is the universal method for loading dictionaries.
/// Expects micado dic.bin format.
pub fn load_from_bytes(bytes : Bytes) -> LoadResult {
  let ok = @runtime.load_dic_bin(bytes[:])
  if ok {
    let count = @runtime.entry_count()
    LoadResult::ok("loaded \{count} entries")
  } else {
    let err = @runtime.last_error()
    LoadResult::error("failed to load dictionary: \{err}")
  }
}

///|
/// Load MeCab dictionary from raw bytes (sys.dic + matrix.bin).
///
/// DEPRECATED: Direct loading of MeCab binary format is no longer supported.
/// Please convert to micado format first using:
///   node tools/dict-compiler/scripts/convert_mecab.mjs <mecab-dic-dir> -o output.dic.bin
///
/// This function will parse the dictionary but cannot load it into runtime.
pub fn load_mecab_from_bytes(
  sys_dic_bytes : Bytes,
  matrix_bytes : Bytes,
) -> LoadResult {
  // MeCab binary format is no longer directly supported
  // The Double-Array Trie extraction is complex and error-prone
  // Users should use the CSV source files via convert_mecab.mjs instead
  let _ = sys_dic_bytes
  let _ = matrix_bytes
  LoadResult::error(
    "MeCab binary format (sys.dic + matrix.bin) is no longer supported. Please convert to micado format using: node tools/dict-compiler/scripts/convert_mecab.mjs <mecab-dic-dir> -o output.dic.bin",
  )
}

///|
/// Check if dictionary is ready for use
pub fn is_ready() -> Bool {
  @runtime.is_ready()
}

///|
/// Get the number of loaded dictionary entries
pub fn entry_count() -> Int {
  @runtime.entry_count()
}
