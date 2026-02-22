///|
let default_connection_cost = 10000

///|
let runtime_ready : Ref[Bool] = @ref.new(false)

///|
let runtime_entries : Ref[Array[@types.DictEntry]] = @ref.new([])

///|
let runtime_surface_index : Ref[@hashmap.HashMap[String, Array[Int]]] = @ref.new(
  @hashmap.new(),
)

///|
let runtime_max_surface_len : Ref[Int] = @ref.new(0)

///|
let runtime_connection_ids : Ref[Array[Int]] = @ref.new([])

///|
let runtime_connection_id_to_index : Ref[@hashmap.HashMap[Int, Int]] = @ref.new(
  @hashmap.new(),
)

///|
let runtime_connection_costs : Ref[Array[Int]] = @ref.new([])

///|
let runtime_connection_width : Ref[Int] = @ref.new(0)

///|
let runtime_connection_default_cost : Ref[Int] = @ref.new(
  default_connection_cost,
)

///|
let runtime_bos_connection_index : Ref[Int] = @ref.new(-1)

///|
let runtime_noun_connection_index : Ref[Int] = @ref.new(-1)

///|
let runtime_unknown_connection_index : Ref[Int] = @ref.new(-1)

///|
let runtime_last_error : Ref[String] = @ref.new("")

///|
/// Reading index: hiragana reading -> array of entry indices
let runtime_reading_index : Ref[@hashmap.HashMap[String, Array[Int]]] = @ref.new(
  @hashmap.new(),
)

///|
fn clear_runtime_state() -> Unit {
  runtime_ready.val = false
  runtime_entries.val = []
  runtime_surface_index.val = @hashmap.new()
  runtime_max_surface_len.val = 0
  runtime_connection_ids.val = []
  runtime_connection_id_to_index.val = @hashmap.new()
  runtime_connection_costs.val = []
  runtime_connection_width.val = 0
  runtime_connection_default_cost.val = default_connection_cost
  runtime_bos_connection_index.val = -1
  runtime_noun_connection_index.val = -1
  runtime_unknown_connection_index.val = -1
  runtime_reading_index.val = @hashmap.new()
}

///|
fn fail_with(message : String) -> Bool {
  runtime_last_error.val = message
  clear_runtime_state()
  false
}

///|
pub fn is_ready() -> Bool {
  runtime_ready.val
}

///|
pub fn entry_count() -> Int {
  runtime_entries.val.length()
}

///|
pub fn max_surface_length() -> Int {
  runtime_max_surface_len.val
}

///|
pub fn connection_id_count() -> Int {
  runtime_connection_ids.val.length()
}

///|
pub fn last_error() -> String {
  runtime_last_error.val
}

///|
fn has_range(bytes : BytesView, offset : Int, size : Int) -> Bool {
  offset >= 0 && size >= 0 && offset + size <= bytes.length()
}

///|
fn read_u16_le(bytes : BytesView, offset : Int) -> Int {
  bytes[offset].to_int() | (bytes[offset + 1].to_int() << 8)
}

///|
fn read_i16_le(bytes : BytesView, offset : Int) -> Int {
  let u = read_u16_le(bytes, offset)
  if u >= 0x8000 {
    u - 0x10000
  } else {
    u
  }
}

///|
fn read_u32_le_non_negative(bytes : BytesView, offset : Int) -> Int {
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  let b2 = bytes[offset + 2].to_int()
  let b3 = bytes[offset + 3].to_int()
  if b3 >= 0x80 {
    -1
  } else {
    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  }
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
fn safe_field(cols : Array[String], index : Int, fallback : String) -> String {
  if index >= cols.length() {
    return fallback
  }
  let value = cols[index]
  if value.length() == 0 {
    fallback
  } else {
    value
  }
}

///|
fn pos_class_from_fields(pos1 : String, pos2 : String) -> @types.POS {
  if pos1 == "名詞" {
    if pos2 == "固有名詞" {
      return @types.POS::NounProper
    }
    if pos2 == "非自立" {
      return @types.POS::NounNonIndependent
    }
    return @types.POS::NounGeneral
  }
  if pos1 == "助詞" {
    return @types.POS::Particle
  }
  if pos1 == "BOS/EOS" {
    return @types.POS::BosEos
  }
  @types.POS::Unknown
}

///|
fn pos_class_from_tab(pos : String) -> @types.POS {
  if pos.has_prefix("名詞-固有名詞") {
    return @types.POS::NounProper
  }
  if pos.has_prefix("名詞-非自立") {
    return @types.POS::NounNonIndependent
  }
  if pos.has_prefix("名詞") {
    return @types.POS::NounGeneral
  }
  if pos.has_prefix("助詞") {
    return @types.POS::Particle
  }
  if pos.has_prefix("BOS/EOS") {
    return @types.POS::BosEos
  }
  @types.POS::Unknown
}

///|
fn parse_pos_and_detail(feature : String) -> (@types.POS, String) {
  if feature.length() == 0 {
    return (@types.POS::Unknown, "未知語,*,*,*")
  }
  if feature.find("\t") is Some(_) {
    let cols = feature.split("\t").map(StringView::to_string).collect()
    let pos = safe_field(cols, 3, "未知語")
    return (pos_class_from_tab(pos), pos)
  }
  let cols = feature.split(",").map(StringView::to_string).collect()
  let c0 = safe_field(cols, 0, "未知語")
  let c1 = safe_field(cols, 1, "*")
  let c2 = safe_field(cols, 2, "*")
  let c3 = safe_field(cols, 3, "*")
  (pos_class_from_fields(c0, c1), "\{c0},\{c1},\{c2},\{c3}")
}

///|
fn build_surface_index(
  entries : Array[@types.DictEntry],
) -> (@hashmap.HashMap[String, Array[Int]], Int) {
  let index : @hashmap.HashMap[String, Array[Int]] = @hashmap.new(
    capacity=entries.length(),
  )
  let mut max_surface_len = 0
  for i in 0..<entries.length() {
    let surface = entries[i].surface
    let len = surface.to_array().length()
    if len > max_surface_len {
      max_surface_len = len
    }
    match index.get(surface) {
      Some(bucket) => bucket.push(i)
      None => index.set(surface, [i])
    }
  }
  (index, max_surface_len)
}

///|
/// Extract reading from MeCab feature string (field index 7)
/// Format: pos1,pos2,pos3,pos4,cType,cForm,base,reading,pronunciation
pub fn extract_reading_from_feature(feature : String) -> String {
  let mut field_index = 0
  let mut start = 0
  for i, ch in feature {
    if ch == ',' {
      if field_index == 7 {
        let reading = feature[start:i].to_string() catch { _ => "" }
        if reading != "*" && reading.length() > 0 {
          return reading
        }
        return ""
      }
      field_index = field_index + 1
      start = i + 1
    }
  }
  // Handle last field (index 7 or 8)
  if field_index == 7 {
    let reading = feature[start:].to_string() catch { _ => "" }
    if reading != "*" && reading.length() > 0 {
      return reading
    }
  }
  ""
}

///|
/// Convert katakana to hiragana for reading index
/// Katakana: U+30A1-U+30F6, Hiragana: U+3041-U+3096 (offset: 0x60)
pub fn katakana_to_hiragana(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new(size_hint=chars.length())
  for ch in chars {
    let cp = ch.to_int()
    if cp >= 0x30A1 && cp <= 0x30F6 {
      buf.write_char((cp - 0x60).unsafe_to_char())
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Build reading index from entries
fn build_reading_index(
  entries : Array[@types.DictEntry],
) -> @hashmap.HashMap[String, Array[Int]] {
  let index : @hashmap.HashMap[String, Array[Int]] = @hashmap.new(
    capacity=entries.length(),
  )
  for i in 0..<entries.length() {
    let reading = extract_reading_from_feature(entries[i].mecab_feature)
    if reading.length() > 0 {
      let hiragana = katakana_to_hiragana(reading)
      match index.get(hiragana) {
        Some(bucket) => bucket.push(i)
        None => index.set(hiragana, [i])
      }
    }
  }
  index
}

///|
fn connection_index_or_missing_from_map(
  id_to_index : @hashmap.HashMap[Int, Int],
  raw_id : Int,
) -> Int {
  match id_to_index.get(raw_id) {
    Some(index) => index
    None => -1
  }
}

///|
fn remap_entry_connection_ids(
  entries : Array[@types.DictEntry],
  id_to_index : @hashmap.HashMap[Int, Int],
) -> Unit {
  for i in 0..<entries.length() {
    let entry = entries[i]
    entries[i] = {
      ..entry,
      left_id: connection_index_or_missing_from_map(id_to_index, entry.left_id),
      right_id: connection_index_or_missing_from_map(
        id_to_index,
        entry.right_id,
      ),
    }
  }
}

///|
fn parse_and_set_runtime(bytes : BytesView) -> Bool {
  let header_size = 24
  let record_size = 24
  let matrix_header_size = 20
  if bytes.length() < header_size {
    return fail_with("dic.bin too small")
  }
  if bytes[0].to_int() != 0x4D ||
    bytes[1].to_int() != 0x44 ||
    bytes[2].to_int() != 0x49 ||
    bytes[3].to_int() != 0x43 {
    return fail_with("dic.bin magic mismatch")
  }
  if bytes[4].to_int() != 1 {
    return fail_with("unsupported dic.bin version")
  }
  let entry_count = read_u32_le_non_negative(bytes, 8)
  let index_offset = read_u32_le_non_negative(bytes, 12)
  let record_bytes = read_u32_le_non_negative(bytes, 16)
  let strings_offset = read_u32_le_non_negative(bytes, 20)
  if entry_count < 0 ||
    index_offset < 0 ||
    record_bytes < 0 ||
    strings_offset < 0 {
    return fail_with("dic.bin header is out of supported range")
  }
  if record_bytes != entry_count * record_size {
    return fail_with("dic.bin index size mismatch")
  }
  if strings_offset != index_offset + record_bytes {
    return fail_with("dic.bin strings offset mismatch")
  }
  if !has_range(bytes, strings_offset, 0) {
    return fail_with("dic.bin strings offset out of range")
  }
  if !has_range(bytes, index_offset, record_bytes) {
    return fail_with("dic.bin index section out of range")
  }
  let entries : Array[@types.DictEntry] = Array::new(capacity=entry_count)
  let mut strings_end = strings_offset
  for i in 0..<entry_count {
    let rec = index_offset + i * record_size
    if !has_range(bytes, rec, record_size) {
      return fail_with("dic.bin record out of range")
    }
    let s_off = read_u32_le_non_negative(bytes, rec + 0)
    let s_len = read_u16_le(bytes, rec + 4)
    let f_off = read_u32_le_non_negative(bytes, rec + 8)
    let f_len = read_u16_le(bytes, rec + 12)
    let left_id = read_i16_le(bytes, rec + 16)
    let right_id = read_i16_le(bytes, rec + 18)
    let word_cost = read_i32_le(bytes, rec + 20)
    if s_off < 0 || f_off < 0 {
      return fail_with("dic.bin string offset out of supported range")
    }
    let s_start = strings_offset + s_off
    let s_end = s_start + s_len
    let f_start = strings_offset + f_off
    let f_end = f_start + f_len
    if !has_range(bytes, s_start, s_len) || !has_range(bytes, f_start, f_len) {
      return fail_with("dic.bin string range out of bounds")
    }
    if s_end > strings_end {
      strings_end = s_end
    }
    if f_end > strings_end {
      strings_end = f_end
    }
    let surface = @utf8.decode_lossy(bytes[s_start:s_end])
    let feature = @utf8.decode_lossy(bytes[f_start:f_end])
    let (pos, pos_detail) = parse_pos_and_detail(feature)
    entries.push({
      surface,
      pos,
      pos_detail,
      mecab_feature: feature,
      left_id,
      right_id,
      word_cost,
    })
  }
  if !has_range(bytes, strings_end, matrix_header_size) {
    return fail_with("dic.bin matrix section is missing")
  }
  if bytes[strings_end + 0].to_int() != 0x4D ||
    bytes[strings_end + 1].to_int() != 0x54 ||
    bytes[strings_end + 2].to_int() != 0x58 ||
    bytes[strings_end + 3].to_int() != 0x31 {
    return fail_with("dic.bin matrix section magic mismatch")
  }
  let num_ids = read_u32_le_non_negative(bytes, strings_end + 4)
  let default_cost = read_i32_le(bytes, strings_end + 8)
  let ids_bytes = read_u32_le_non_negative(bytes, strings_end + 12)
  let costs_bytes = read_u32_le_non_negative(bytes, strings_end + 16)
  if num_ids < 0 || ids_bytes < 0 || costs_bytes < 0 {
    return fail_with("dic.bin matrix section out of supported range")
  }
  if ids_bytes != num_ids * 2 {
    return fail_with("dic.bin matrix ids size mismatch")
  }
  if costs_bytes != num_ids * num_ids * 2 {
    return fail_with("dic.bin matrix cost size mismatch")
  }
  let ids_offset = strings_end + matrix_header_size
  let costs_offset = ids_offset + ids_bytes
  if !has_range(bytes, ids_offset, ids_bytes) ||
    !has_range(bytes, costs_offset, costs_bytes) {
    return fail_with("dic.bin matrix section out of range")
  }
  let ids : Array[Int] = Array::makei(num_ids, _ => 0)
  let id_to_index : @hashmap.HashMap[Int, Int] = @hashmap.new(capacity=num_ids)
  for i in 0..<num_ids {
    let id = read_i16_le(bytes, ids_offset + i * 2)
    ids[i] = id
    id_to_index.set(id, i)
  }
  let costs : Array[Int] = Array::makei(num_ids * num_ids, _ => 0)
  for i in 0..<costs.length() {
    costs[i] = read_i16_le(bytes, costs_offset + i * 2)
  }
  remap_entry_connection_ids(entries, id_to_index)
  let (surface_index, max_surface_len) = build_surface_index(entries)
  let reading_index = build_reading_index(entries)
  runtime_entries.val = entries
  runtime_surface_index.val = surface_index
  runtime_max_surface_len.val = max_surface_len
  runtime_reading_index.val = reading_index
  runtime_connection_ids.val = ids
  runtime_connection_id_to_index.val = id_to_index
  runtime_connection_costs.val = costs
  runtime_connection_width.val = num_ids
  runtime_connection_default_cost.val = default_cost
  runtime_bos_connection_index.val = connection_index_or_missing_from_map(
    id_to_index, 0,
  )
  runtime_noun_connection_index.val = connection_index_or_missing_from_map(
    id_to_index, 1,
  )
  runtime_unknown_connection_index.val = connection_index_or_missing_from_map(
    id_to_index, 3,
  )
  runtime_last_error.val = ""
  runtime_ready.val = true
  true
}

///|
pub fn load_dic_bin(bytes : BytesView) -> Bool {
  parse_and_set_runtime(bytes)
}

///|
pub fn bos_connection_index() -> Int {
  if !runtime_ready.val {
    return -1
  }
  runtime_bos_connection_index.val
}

///|
pub fn noun_connection_index() -> Int {
  if !runtime_ready.val {
    return -1
  }
  runtime_noun_connection_index.val
}

///|
pub fn unknown_connection_index() -> Int {
  if !runtime_ready.val {
    return -1
  }
  runtime_unknown_connection_index.val
}

///|
pub fn connection_id_to_index_or_missing(raw_id : Int) -> Int {
  if !runtime_ready.val {
    return -1
  }
  connection_index_or_missing_from_map(
    runtime_connection_id_to_index.val,
    raw_id,
  )
}

///|
pub fn connection_cost_by_index(right_index : Int, left_index : Int) -> Int {
  if !runtime_ready.val {
    return default_connection_cost
  }
  if right_index < 0 || left_index < 0 {
    return runtime_connection_default_cost.val
  }
  let width = runtime_connection_width.val
  let flat = right_index * width + left_index
  if flat >= 0 && flat < runtime_connection_costs.val.length() {
    return runtime_connection_costs.val[flat]
  }
  runtime_connection_default_cost.val
}

///|
pub fn connection_cost(right_id : Int, left_id : Int) -> Int {
  let right_index = connection_id_to_index_or_missing(right_id)
  let left_index = connection_id_to_index_or_missing(left_id)
  connection_cost_by_index(right_index, left_index)
}

///|
pub fn append_dictionary_candidates(
  dst : Array[@types.TokenCandidate],
  chars : Array[Char],
  pos : Int,
) -> Unit {
  if !runtime_ready.val {
    return
  }
  let remaining = chars.length() - pos
  if remaining <= 0 {
    return
  }
  let limit = if runtime_max_surface_len.val < remaining {
    runtime_max_surface_len.val
  } else {
    remaining
  }
  for len in 1..<=limit {
    let surface = @types.chars_slice(chars, pos, pos + len)
    match runtime_surface_index.val.get(surface) {
      Some(indexes) =>
        for entry_index in indexes {
          let entry = runtime_entries.val[entry_index]
          dst.push({
            start_pos: pos,
            end_pos: pos + len,
            pos: entry.pos,
            pos_detail: entry.pos_detail,
            mecab_feature: entry.mecab_feature,
            left_id: entry.left_id,
            right_id: entry.right_id,
            word_cost: entry.word_cost,
          })
        }
      None => ()
    }
  }
}

///|
/// Parsed dictionary data (local, not yet merged into runtime state)
priv struct ParsedDicData {
  entries : Array[@types.DictEntry]
  ids : Array[Int]
  costs : Array[Int]
  num_ids : Int
}

///|
/// Parse dic.bin bytes into local data structure without modifying global state.
/// Entry left_id/right_id remain as raw IDs (not remapped).
fn parse_dic_bin_to_local(bytes : BytesView) -> ParsedDicData? {
  let header_size = 24
  let record_size = 24
  let matrix_header_size = 20
  if bytes.length() < header_size {
    runtime_last_error.val = "merge: dic.bin too small"
    return None
  }
  if bytes[0].to_int() != 0x4D ||
    bytes[1].to_int() != 0x44 ||
    bytes[2].to_int() != 0x49 ||
    bytes[3].to_int() != 0x43 {
    runtime_last_error.val = "merge: dic.bin magic mismatch"
    return None
  }
  if bytes[4].to_int() != 1 {
    runtime_last_error.val = "merge: unsupported dic.bin version"
    return None
  }
  let entry_count = read_u32_le_non_negative(bytes, 8)
  let index_offset = read_u32_le_non_negative(bytes, 12)
  let record_bytes = read_u32_le_non_negative(bytes, 16)
  let strings_offset = read_u32_le_non_negative(bytes, 20)
  if entry_count < 0 ||
    index_offset < 0 ||
    record_bytes < 0 ||
    strings_offset < 0 {
    runtime_last_error.val = "merge: dic.bin header out of supported range"
    return None
  }
  if record_bytes != entry_count * record_size {
    runtime_last_error.val = "merge: dic.bin index size mismatch"
    return None
  }
  if strings_offset != index_offset + record_bytes {
    runtime_last_error.val = "merge: dic.bin strings offset mismatch"
    return None
  }
  if !has_range(bytes, strings_offset, 0) {
    runtime_last_error.val = "merge: dic.bin strings offset out of range"
    return None
  }
  if !has_range(bytes, index_offset, record_bytes) {
    runtime_last_error.val = "merge: dic.bin index section out of range"
    return None
  }
  let entries : Array[@types.DictEntry] = Array::new(capacity=entry_count)
  let mut strings_end = strings_offset
  for i in 0..<entry_count {
    let rec = index_offset + i * record_size
    if !has_range(bytes, rec, record_size) {
      runtime_last_error.val = "merge: dic.bin record out of range"
      return None
    }
    let s_off = read_u32_le_non_negative(bytes, rec + 0)
    let s_len = read_u16_le(bytes, rec + 4)
    let f_off = read_u32_le_non_negative(bytes, rec + 8)
    let f_len = read_u16_le(bytes, rec + 12)
    let left_id = read_i16_le(bytes, rec + 16)
    let right_id = read_i16_le(bytes, rec + 18)
    let word_cost = read_i32_le(bytes, rec + 20)
    if s_off < 0 || f_off < 0 {
      runtime_last_error.val = "merge: dic.bin string offset out of supported range"
      return None
    }
    let s_start = strings_offset + s_off
    let s_end = s_start + s_len
    let f_start = strings_offset + f_off
    let f_end = f_start + f_len
    if !has_range(bytes, s_start, s_len) || !has_range(bytes, f_start, f_len) {
      runtime_last_error.val = "merge: dic.bin string range out of bounds"
      return None
    }
    if s_end > strings_end {
      strings_end = s_end
    }
    if f_end > strings_end {
      strings_end = f_end
    }
    let surface = @utf8.decode_lossy(bytes[s_start:s_end])
    let feature = @utf8.decode_lossy(bytes[f_start:f_end])
    let (pos, pos_detail) = parse_pos_and_detail(feature)
    // Note: left_id and right_id are kept as raw IDs (not remapped)
    entries.push({
      surface,
      pos,
      pos_detail,
      mecab_feature: feature,
      left_id,
      right_id,
      word_cost,
    })
  }
  if !has_range(bytes, strings_end, matrix_header_size) {
    runtime_last_error.val = "merge: dic.bin matrix section is missing"
    return None
  }
  if bytes[strings_end + 0].to_int() != 0x4D ||
    bytes[strings_end + 1].to_int() != 0x54 ||
    bytes[strings_end + 2].to_int() != 0x58 ||
    bytes[strings_end + 3].to_int() != 0x31 {
    runtime_last_error.val = "merge: dic.bin matrix section magic mismatch"
    return None
  }
  let num_ids = read_u32_le_non_negative(bytes, strings_end + 4)
  let _default_cost = read_i32_le(bytes, strings_end + 8)
  let ids_bytes = read_u32_le_non_negative(bytes, strings_end + 12)
  let costs_bytes = read_u32_le_non_negative(bytes, strings_end + 16)
  if num_ids < 0 || ids_bytes < 0 || costs_bytes < 0 {
    runtime_last_error.val = "merge: dic.bin matrix section out of supported range"
    return None
  }
  if ids_bytes != num_ids * 2 {
    runtime_last_error.val = "merge: dic.bin matrix ids size mismatch"
    return None
  }
  if costs_bytes != num_ids * num_ids * 2 {
    runtime_last_error.val = "merge: dic.bin matrix cost size mismatch"
    return None
  }
  let ids_offset = strings_end + matrix_header_size
  let costs_offset = ids_offset + ids_bytes
  if !has_range(bytes, ids_offset, ids_bytes) ||
    !has_range(bytes, costs_offset, costs_bytes) {
    runtime_last_error.val = "merge: dic.bin matrix section out of range"
    return None
  }
  let ids : Array[Int] = Array::makei(num_ids, fn(_i) { 0 })
  for i in 0..<num_ids {
    ids[i] = read_i16_le(bytes, ids_offset + i * 2)
  }
  let costs : Array[Int] = Array::makei(num_ids * num_ids, fn(_i) { 0 })
  for i in 0..<costs.length() {
    costs[i] = read_i16_le(bytes, costs_offset + i * 2)
  }
  Some({ entries, ids, costs, num_ids })
}

///|
/// Merge an additional dictionary into the existing runtime state.
/// The base dictionary must already be loaded via load_dic_bin().
///
/// Behavior:
/// - Entries from the additional dictionary are appended to runtime_entries
/// - Connection IDs are unified (union of both ID sets)
/// - Connection matrix is expanded to accommodate all IDs
/// - Costs from additional dictionary fill in cells not covered by base
///
/// Returns:
/// - true on success
/// - false on error (use last_error() to get error message)
pub fn merge_dic_bin(bytes : BytesView) -> Bool {
  // Step 1: Check precondition
  if !runtime_ready.val {
    runtime_last_error.val = "merge: no base dictionary loaded"
    return false
  }

  // Step 2: Parse additional dictionary
  let add_data = match parse_dic_bin_to_local(bytes) {
    Some(data) => data
    None => return false
  }

  // Step 3: Build unified connection ID set
  let existing_ids = runtime_connection_ids.val
  let existing_width = runtime_connection_width.val

  // Create unified ID list: existing IDs + new IDs not in existing
  let unified_ids : Array[Int] = Array::new(
    capacity=existing_ids.length() + add_data.num_ids,
  )
  let unified_id_to_index : @hashmap.HashMap[Int, Int] = @hashmap.new()

  // Keep existing IDs in their current positions (indices 0..existing_width-1)
  for i in 0..<existing_ids.length() {
    let raw_id = existing_ids[i]
    unified_ids.push(raw_id)
    unified_id_to_index.set(raw_id, i)
  }

  // Add new IDs that don't exist in the base dictionary
  // These get indices starting at existing_width
  for i in 0..<add_data.num_ids {
    let raw_id = add_data.ids[i]
    if unified_id_to_index.get(raw_id) is None {
      let new_index = unified_ids.length()
      unified_ids.push(raw_id)
      unified_id_to_index.set(raw_id, new_index)
    }
  }

  let unified_width = unified_ids.length()

  // Step 4: Create expanded connection matrix
  let existing_costs = runtime_connection_costs.val
  let unified_costs : Array[Int] = Array::makei(
    unified_width * unified_width,
    fn(_i) { runtime_connection_default_cost.val },
  )

  // Copy existing costs to their positions (unchanged, top-left quadrant)
  for r in 0..<existing_width {
    for c in 0..<existing_width {
      let old_flat = r * existing_width + c
      let new_flat = r * unified_width + c
      unified_costs[new_flat] = existing_costs[old_flat]
    }
  }

  // Build mapping: additional dict index -> unified index
  let add_idx_to_unified : Array[Int] = Array::makei(
    add_data.num_ids,
    fn(_i) { -1 },
  )
  for i in 0..<add_data.num_ids {
    let raw_id = add_data.ids[i]
    match unified_id_to_index.get(raw_id) {
      Some(idx) => add_idx_to_unified[i] = idx
      None => ()
    }
  }

  // Fill cells with costs from additional dictionary
  // Only write if the cell is NEW (not from existing quadrant)
  for add_r in 0..<add_data.num_ids {
    for add_c in 0..<add_data.num_ids {
      let unified_r = add_idx_to_unified[add_r]
      let unified_c = add_idx_to_unified[add_c]
      if unified_r >= 0 && unified_c >= 0 {
        let was_in_existing = unified_r < existing_width &&
          unified_c < existing_width
        if !was_in_existing {
          let add_flat = add_r * add_data.num_ids + add_c
          let new_flat = unified_r * unified_width + unified_c
          unified_costs[new_flat] = add_data.costs[add_flat]
        }
      }
    }
  }

  // Step 5: Remap and append new entries
  let existing_entry_count = runtime_entries.val.length()

  for entry in add_data.entries {
    let unified_left = connection_index_or_missing_from_map(
      unified_id_to_index,
      entry.left_id,
    )
    let unified_right = connection_index_or_missing_from_map(
      unified_id_to_index,
      entry.right_id,
    )
    runtime_entries.val.push({
      ..entry,
      left_id: unified_left,
      right_id: unified_right,
    })
  }

  // Update surface index with new entries
  for i in existing_entry_count..<runtime_entries.val.length() {
    let entry = runtime_entries.val[i]
    let surface = entry.surface
    let len = surface.to_array().length()
    if len > runtime_max_surface_len.val {
      runtime_max_surface_len.val = len
    }
    match runtime_surface_index.val.get(surface) {
      Some(bucket) => bucket.push(i)
      None => runtime_surface_index.val.set(surface, [i])
    }
  }

  // Update reading index with new entries
  for i in existing_entry_count..<runtime_entries.val.length() {
    let entry = runtime_entries.val[i]
    let reading = extract_reading_from_feature(entry.mecab_feature)
    if reading.length() > 0 {
      let hiragana = katakana_to_hiragana(reading)
      match runtime_reading_index.val.get(hiragana) {
        Some(bucket) => bucket.push(i)
        None => runtime_reading_index.val.set(hiragana, [i])
      }
    }
  }

  // Step 6: Update global state
  runtime_connection_ids.val = unified_ids
  runtime_connection_id_to_index.val = unified_id_to_index
  runtime_connection_costs.val = unified_costs
  runtime_connection_width.val = unified_width

  // Update special ID indices (may have changed if IDs were newly added)
  runtime_bos_connection_index.val = connection_index_or_missing_from_map(
    unified_id_to_index,
    0,
  )
  runtime_noun_connection_index.val = connection_index_or_missing_from_map(
    unified_id_to_index,
    1,
  )
  runtime_unknown_connection_index.val = connection_index_or_missing_from_map(
    unified_id_to_index,
    3,
  )

  runtime_last_error.val = ""
  true
}

///|
/// Get a single entry by index (for IME module access)
pub fn get_entry(index : Int) -> @types.DictEntry? {
  if !runtime_ready.val {
    return None
  }
  if index < 0 || index >= runtime_entries.val.length() {
    return None
  }
  Some(runtime_entries.val[index])
}

///|
/// Get all dictionary entries as RuntimeEntry array (for custom indexing)
pub fn get_all_entries() -> Array[@types.RuntimeEntry] {
  if !runtime_ready.val {
    return []
  }
  let entries = runtime_entries.val
  let result : Array[@types.RuntimeEntry] = Array::new(capacity=entries.length())
  for entry in entries {
    result.push({
      surface: entry.surface,
      left_id: entry.left_id,
      right_id: entry.right_id,
      word_cost: entry.word_cost,
      feature: entry.mecab_feature,
    })
  }
  result
}

///|
/// Get entry indices by hiragana reading (for IME lookup)
pub fn get_entries_by_reading(reading : String) -> Array[Int] {
  if !runtime_ready.val {
    return []
  }
  match runtime_reading_index.val.get(reading) {
    Some(indices) => indices.copy()
    None => []
  }
}

///|
/// Get all readings in the index (for prefix search)
pub fn get_all_readings() -> Array[String] {
  if !runtime_ready.val {
    return []
  }
  runtime_reading_index.val.keys().collect()
}
