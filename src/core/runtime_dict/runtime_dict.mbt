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
let runtime_last_error : Ref[String] = @ref.new("")

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
  runtime_entries.val = entries
  runtime_surface_index.val = surface_index
  runtime_max_surface_len.val = max_surface_len
  runtime_connection_ids.val = ids
  runtime_connection_id_to_index.val = id_to_index
  runtime_connection_costs.val = costs
  runtime_connection_width.val = num_ids
  runtime_connection_default_cost.val = default_cost
  runtime_last_error.val = ""
  runtime_ready.val = true
  true
}

///|
pub fn load_dic_bin(bytes : BytesView) -> Bool {
  parse_and_set_runtime(bytes)
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
