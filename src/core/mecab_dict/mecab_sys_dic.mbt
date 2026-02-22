///|
/// MeCab sys.dic binary format parser
///
/// Binary structure:
/// - Header (72 bytes): magic, version, type, sizes, charset
/// - Double-Array Trie: base[] and check[] arrays for surface lookup
/// - Token array: morpheme information (lcAttr, rcAttr, wcost, feature offset)
/// - Feature strings: null-terminated strings pool

/// MeCab magic XOR constant (magic ^ file_size = MAGIC_ID)
let mecab_magic_id : UInt = 0xEF718F77

/// MeCab dictionary version we support
let mecab_version_supported : UInt = 102

/// Header size in bytes
let mecab_header_size : Int = 72

/// Token record size in bytes
let mecab_token_size : Int = 16

///|
/// MeCab dictionary header
pub struct MecabDicHeader {
  magic : UInt
  version : UInt
  dic_type : UInt  // 0=sys, 1=usr, 2=unk
  lexsize : UInt   // number of lexicon entries (tokens)
  lsize : UInt     // left context size (number of left IDs)
  rsize : UInt     // right context size (number of right IDs)
  dsize : UInt     // double-array size IN BYTES (divide by 8 for element count)
  tsize : UInt     // token array size IN BYTES (divide by 16 for token count)
  fsize : UInt     // feature string pool size IN BYTES
  charset : String
}

///|
/// Double-Array element
struct DAElement {
  base : Int
  check : Int
}

///|
/// Token record from sys.dic
struct MecabToken {
  left_attr : Int   // left context id
  right_attr : Int  // right context id
  posid : Int       // POS id (unused in our impl)
  wcost : Int       // word cost
  feature_offset : UInt  // offset into feature string pool
}

///|
/// Parsed MeCab dictionary
pub struct MecabDictionary {
  header : MecabDicHeader
  da_base : Array[Int]
  da_check : Array[Int]
  tokens : Array[MecabToken]
  features : Bytes  // raw feature string pool
}

///|
fn read_u32_le(bytes : BytesView, offset : Int) -> UInt {
  let b0 = bytes[offset].to_int().reinterpret_as_uint()
  let b1 = bytes[offset + 1].to_int().reinterpret_as_uint()
  let b2 = bytes[offset + 2].to_int().reinterpret_as_uint()
  let b3 = bytes[offset + 3].to_int().reinterpret_as_uint()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn read_i32_le(bytes : BytesView, offset : Int) -> Int {
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  let b2 = bytes[offset + 2].to_int()
  let b3 = bytes[offset + 3].to_int()
  let low = b0 | (b1 << 8) | (b2 << 16)
  if b3 >= 0x80 {
    low | ((b3 - 0x100) << 24)
  } else {
    low | (b3 << 24)
  }
}

///|
fn read_i16_le(bytes : BytesView, offset : Int) -> Int {
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  let u = b0 | (b1 << 8)
  if u >= 0x8000 {
    u - 0x10000
  } else {
    u
  }
}

///|
fn read_u16_le(bytes : BytesView, offset : Int) -> UInt {
  let b0 = bytes[offset].to_int().reinterpret_as_uint()
  let b1 = bytes[offset + 1].to_int().reinterpret_as_uint()
  b0 | (b1 << 8)
}

///|
fn read_cstring(bytes : BytesView, offset : Int, max_len : Int) -> String {
  let buf = @buffer.new(size_hint=max_len)
  for i = 0; i < max_len; i = i + 1 {
    let b = bytes[offset + i]
    if b == b'\x00' {
      break
    }
    buf.write_byte(b)
  }
  @utf8.decode_lossy(buf.to_bytes()[:])
}

///|
fn parse_header(bytes : BytesView) -> MecabDicHeader? {
  if bytes.length() < mecab_header_size {
    return None
  }
  let magic = read_u32_le(bytes, 0)
  let version = read_u32_le(bytes, 4)
  let dic_type = read_u32_le(bytes, 8)
  let lexsize = read_u32_le(bytes, 12)
  let lsize = read_u32_le(bytes, 16)
  let rsize = read_u32_le(bytes, 20)
  let dsize = read_u32_le(bytes, 24)
  let tsize = read_u32_le(bytes, 28)
  let fsize = read_u32_le(bytes, 32)
  // bytes 36-39: dummy/padding
  let charset = read_cstring(bytes, 40, 32)
  Some({
    magic,
    version,
    dic_type,
    lexsize,
    lsize,
    rsize,
    dsize,
    tsize,
    fsize,
    charset,
  })
}

///|
/// Parse MeCab sys.dic binary
pub fn parse_mecab_sys_dic(bytes : BytesView) -> (MecabDictionary?, String) {
  // Parse header
  let header = match parse_header(bytes) {
    Some(h) => h
    None => return (None, "sys.dic too small for header")
  }

  // Validate magic: magic XOR MAGIC_ID should equal file size
  let expected_size_from_magic = (header.magic ^ mecab_magic_id).reinterpret_as_int()
  if expected_size_from_magic != bytes.length() {
    return (None, "sys.dic magic validation failed (magic XOR 0xEF718F77 = \{expected_size_from_magic}, file size = \{bytes.length()})")
  }

  // Validate version
  if header.version != mecab_version_supported {
    return (None, "sys.dic version \{header.version} not supported (expected \{mecab_version_supported})")
  }

  // Calculate section offsets (dsize, tsize, fsize are in BYTES)
  let da_offset = mecab_header_size
  let da_bytes = header.dsize.reinterpret_as_int()
  let token_offset = da_offset + da_bytes
  let token_bytes = header.tsize.reinterpret_as_int()
  let feature_offset = token_offset + token_bytes
  let feature_size = header.fsize.reinterpret_as_int()
  let expected_size = feature_offset + feature_size

  if bytes.length() < expected_size {
    return (None, "sys.dic truncated (expected \{expected_size} bytes, got \{bytes.length()})")
  }

  // Parse Double-Array (8 bytes per element: base + check)
  let da_count = da_bytes / 8
  let da_base : Array[Int] = Array::make(da_count, 0)
  let da_check : Array[Int] = Array::make(da_count, 0)
  for i = 0; i < da_count; i = i + 1 {
    let elem_offset = da_offset + i * 8
    da_base[i] = read_i32_le(bytes, elem_offset)
    da_check[i] = read_i32_le(bytes, elem_offset + 4)
  }

  // Parse tokens (16 bytes per token record)
  let token_count = token_bytes / mecab_token_size
  let tokens : Array[MecabToken] = Array::make(token_count, {
    left_attr: 0,
    right_attr: 0,
    posid: 0,
    wcost: 0,
    feature_offset: 0U,
  })
  for i = 0; i < token_count; i = i + 1 {
    let rec_offset = token_offset + i * mecab_token_size
    tokens[i] = {
      left_attr: read_i16_le(bytes, rec_offset),
      right_attr: read_i16_le(bytes, rec_offset + 2),
      posid: read_i16_le(bytes, rec_offset + 4),
      wcost: read_i16_le(bytes, rec_offset + 6),
      feature_offset: read_u32_le(bytes, rec_offset + 8),
      // bytes 12-15: compound data (unused)
    }
  }

  // Extract feature string pool
  let features_buf = @buffer.new(size_hint=feature_size)
  for i = 0; i < feature_size; i = i + 1 {
    features_buf.write_byte(bytes[feature_offset + i])
  }
  let features = features_buf.to_bytes()

  (Some({
    header,
    da_base,
    da_check,
    tokens,
    features,
  }), "")
}

///|
/// Get feature string for a token
pub fn MecabDictionary::get_feature(self : MecabDictionary, token_index : Int) -> String {
  if token_index < 0 || token_index >= self.tokens.length() {
    return ""
  }
  let offset = self.tokens[token_index].feature_offset.reinterpret_as_int()
  if offset >= self.features.length() {
    return ""
  }
  // Read null-terminated string
  let buf = @buffer.new(size_hint=256)
  for i = offset; i < self.features.length(); i = i + 1 {
    let b = self.features[i]
    if b == b'\x00' {
      break
    }
    buf.write_byte(b)
  }
  @utf8.decode_lossy(buf.to_bytes()[:])
}

///|
/// Traverse Double-Array Trie to find entries matching a surface
/// Returns array of token indices
pub fn MecabDictionary::lookup(self : MecabDictionary, surface : String) -> Array[Int] {
  let results : Array[Int] = []
  let encoded = @utf8.encode(surface[:])

  // Start from root node (index 0)
  let mut node = 0

  // Traverse the trie
  for i = 0; i < encoded.length(); i = i + 1 {
    let c = encoded[i].to_int()
    let next = self.da_base[node] + c

    // Check bounds and transition validity
    if next < 0 || next >= self.da_check.length() {
      break
    }
    if self.da_check[next] != node {
      break
    }

    node = next

    // Check for terminal (negative base means token index)
    let base = self.da_base[node]
    if base < 0 {
      // Found a match - extract token index
      // In MeCab, negative base encodes token array offset
      let token_idx = -base - 1
      if token_idx >= 0 && token_idx < self.tokens.length() {
        results.push(token_idx)
      }
    }
  }

  // Also check exact match at final position
  if node < self.da_base.length() {
    // Check for end-of-string marker (byte 0)
    let term = self.da_base[node]
    if term < 0 {
      let token_idx = -term - 1
      if token_idx >= 0 && token_idx < self.tokens.length() {
        // Check if not already in results
        let mut found = false
        for r in results {
          if r == token_idx {
            found = true
            break
          }
        }
        if not(found) {
          results.push(token_idx)
        }
      }
    }
  }

  results
}

///|
/// Get dictionary statistics
pub fn MecabDictionary::stats(self : MecabDictionary) -> String {
  let h = self.header
  "MeCab Dictionary: charset=\{h.charset}, entries=\{h.lexsize}, da_size=\{h.dsize}, tokens=\{h.tsize}, features=\{h.fsize}bytes"
}
