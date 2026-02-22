///|
/// Build a minimal dic.bin for testing
/// entries: Array of (surface, feature, left_id, right_id, word_cost)
/// ids: Array of connection IDs
/// costs: Flattened cost matrix (ids.length() * ids.length())
/// default_cost: Default connection cost
fn build_test_dic_bin(
  entries : Array[(String, String, Int, Int, Int)],
  ids : Array[Int],
  costs : Array[Int],
  default_cost : Int,
) -> Bytes {
  let buf = @buffer.new()

  // Build strings pool first to calculate offsets
  let strings : Array[Bytes] = []
  let string_offsets : Array[(Int, Int, Int, Int)] = [] // (s_off, s_len, f_off, f_len)
  let mut current_offset = 0
  for entry in entries {
    let (surface, feature, _, _, _) = entry
    let s_bytes = @utf8.encode(surface)
    let f_bytes = @utf8.encode(feature)
    let s_off = current_offset
    let s_len = s_bytes.length()
    current_offset = current_offset + s_len
    let f_off = current_offset
    let f_len = f_bytes.length()
    current_offset = current_offset + f_len
    strings.push(s_bytes)
    strings.push(f_bytes)
    string_offsets.push((s_off, s_len, f_off, f_len))
  }

  let header_size = 24
  let record_size = 24
  let entry_count = entries.length()
  let record_bytes = entry_count * record_size
  let strings_offset = header_size + record_bytes

  // Header
  buf.write_byte(b'\x4D') // M
  buf.write_byte(b'\x44') // D
  buf.write_byte(b'\x49') // I
  buf.write_byte(b'\x43') // C
  buf.write_byte(b'\x01') // version
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  write_u32_le(buf, entry_count)
  write_u32_le(buf, header_size)
  write_u32_le(buf, record_bytes)
  write_u32_le(buf, strings_offset)

  // Entry records
  for i, entry in entries {
    let (_, _, left_id, right_id, word_cost) = entry
    let (s_off, s_len, f_off, f_len) = string_offsets[i]
    write_u32_le(buf, s_off)
    write_u16_le(buf, s_len)
    write_u16_le(buf, 0)
    write_u32_le(buf, f_off)
    write_u16_le(buf, f_len)
    write_u16_le(buf, 0)
    write_i16_le(buf, left_id)
    write_i16_le(buf, right_id)
    write_i32_le(buf, word_cost)
  }

  // Strings pool
  for s in strings {
    for b in s {
      buf.write_byte(b)
    }
  }

  // Matrix section
  let num_ids = ids.length()
  let ids_bytes = num_ids * 2
  let costs_bytes = num_ids * num_ids * 2

  buf.write_byte(b'\x4D') // M
  buf.write_byte(b'\x54') // T
  buf.write_byte(b'\x58') // X
  buf.write_byte(b'\x31') // 1
  write_u32_le(buf, num_ids)
  write_i32_le(buf, default_cost)
  write_u32_le(buf, ids_bytes)
  write_u32_le(buf, costs_bytes)

  // IDs array
  for id in ids {
    write_i16_le(buf, id)
  }

  // Costs array
  for cost in costs {
    write_i16_le(buf, cost)
  }

  buf.to_bytes()
}

///|
fn write_u16_le(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte((value & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
}

///|
fn write_i16_le(buf : @buffer.Buffer, value : Int) -> Unit {
  let v = if value < 0 { value + 0x10000 } else { value }
  write_u16_le(buf, v)
}

///|
fn write_u32_le(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte((value & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 24) & 0xFF).to_byte())
}

///|
fn write_i32_le(buf : @buffer.Buffer, value : Int) -> Unit {
  write_u32_le(buf, value)
}

///|
test "merge_dic_bin fails when no base dictionary loaded" {
  // Clear any existing state
  clear_runtime_state()

  let dic = build_test_dic_bin(
    [("猫", "名詞,一般,*,*", 1, 1, 100)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )

  let result = merge_dic_bin(dic[:])
  inspect(result, content="false")
  inspect(last_error(), content="merge: no base dictionary loaded")
}

///|
test "merge_dic_bin appends entries from additional dictionary" {
  clear_runtime_state()

  // Base dictionary with 2 entries
  let base_dic = build_test_dic_bin(
    [
      ("猫", "名詞,一般,*,*", 1, 1, 100),
      ("犬", "名詞,一般,*,*", 1, 1, 100),
    ],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")
  inspect(entry_count(), content="2")

  // Additional dictionary with 2 new entries
  let add_dic = build_test_dic_bin(
    [
      ("鳥", "名詞,一般,*,*", 1, 1, 100),
      ("魚", "名詞,一般,*,*", 1, 1, 100),
    ],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")
  inspect(entry_count(), content="4")
}

///|
test "merge_dic_bin expands connection matrix with new IDs" {
  clear_runtime_state()

  // Base dictionary: IDs [0, 1]
  let base_dic = build_test_dic_bin(
    [("猫", "名詞,一般,*,*", 1, 1, 100)],
    [0, 1],
    [0, 50, 50, 0], // 2x2 matrix
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")
  inspect(connection_id_count(), content="2")

  // Additional dictionary: IDs [0, 1, 5] (5 is new)
  let add_dic = build_test_dic_bin(
    [("鳥", "名詞,固有名詞,*,*", 5, 5, 100)],
    [0, 1, 5],
    [
      0, 100, 200, // row 0
      100, 0, 300, // row 1
      200, 300, 0, // row 5
    ],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")

  // Now should have 3 IDs: [0, 1, 5]
  inspect(connection_id_count(), content="3")

  // Existing costs should be preserved
  // connection_cost_by_index uses indices, not raw IDs
  // Index 0 -> raw ID 0, Index 1 -> raw ID 1
  inspect(connection_cost_by_index(0, 0), content="0")
  inspect(connection_cost_by_index(0, 1), content="50")
  inspect(connection_cost_by_index(1, 0), content="50")
  inspect(connection_cost_by_index(1, 1), content="0")

  // New ID 5 should have costs from additional dictionary
  // Index 2 -> raw ID 5
  inspect(connection_cost_by_index(2, 2), content="0")
}

///|
test "merge_dic_bin allows same surface in both dictionaries" {
  clear_runtime_state()

  // Base dictionary
  let base_dic = build_test_dic_bin(
    [("東京", "名詞,固有名詞,地域,一般", 1, 1, 5000)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")

  // Additional dictionary with same surface but different feature
  let add_dic = build_test_dic_bin(
    [("東京", "名詞,固有名詞,組織,*", 1, 1, 3000)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")

  // Should have 2 entries (not deduplicated)
  inspect(entry_count(), content="2")
}

///|
test "merge_dic_bin updates max_surface_length" {
  clear_runtime_state()

  // Base dictionary with short surface
  let base_dic = build_test_dic_bin(
    [("猫", "名詞,一般,*,*", 1, 1, 100)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")
  let base_max = max_surface_length()

  // Additional dictionary with longer surface
  let add_dic = build_test_dic_bin(
    [("東京スカイツリー", "名詞,固有名詞,一般,*", 1, 1, 100)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")

  // max_surface_length should be updated
  let new_max = max_surface_length()
  inspect(new_max > base_max, content="true")
}

///|
test "merge_dic_bin preserves base dictionary costs for overlapping IDs" {
  clear_runtime_state()

  // Base dictionary: IDs [0, 1] with specific costs
  let base_dic = build_test_dic_bin(
    [("猫", "名詞,一般,*,*", 1, 1, 100)],
    [0, 1],
    [
      0, 111, // row 0: cost[0,0]=0, cost[0,1]=111
      222, 0, // row 1: cost[1,0]=222, cost[1,1]=0
    ],
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")

  // Additional dictionary: same IDs [0, 1] with DIFFERENT costs
  let add_dic = build_test_dic_bin(
    [("鳥", "名詞,一般,*,*", 1, 1, 100)],
    [0, 1],
    [
      0, 999, // row 0: cost[0,0]=0, cost[0,1]=999 (different!)
      888, 0, // row 1: cost[1,0]=888, cost[1,1]=0 (different!)
    ],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")

  // Base dictionary costs should be preserved (not overwritten)
  inspect(connection_cost_by_index(0, 1), content="111") // NOT 999
  inspect(connection_cost_by_index(1, 0), content="222") // NOT 888
}

///|
test "extract_reading_from_feature extracts field 7" {
  // Standard 9-field MeCab feature
  let feature = "名詞,固有名詞,地域,一般,*,*,東京,トウキョウ,トーキョー"
  inspect(extract_reading_from_feature(feature), content="トウキョウ")
}

///|
test "extract_reading_from_feature returns empty for star reading" {
  let feature = "名詞,一般,*,*,*,*,猫,*,*"
  inspect(extract_reading_from_feature(feature), content="")
}

///|
test "extract_reading_from_feature returns empty for short feature" {
  // Feature with only 6 fields (no reading)
  let feature = "名詞,一般,*,*,*,*"
  inspect(extract_reading_from_feature(feature), content="")
}

///|
test "extract_reading_from_feature handles empty string" {
  inspect(extract_reading_from_feature(""), content="")
}

///|
test "katakana_to_hiragana converts standard katakana" {
  inspect(katakana_to_hiragana("トウキョウ"), content="とうきょう")
  inspect(katakana_to_hiragana("ネコ"), content="ねこ")
  inspect(katakana_to_hiragana("カタカナ"), content="かたかな")
}

///|
test "katakana_to_hiragana preserves hiragana" {
  inspect(katakana_to_hiragana("ひらがな"), content="ひらがな")
}

///|
test "katakana_to_hiragana preserves special marks" {
  // Prolonged sound mark (ー) and middle dot (・) pass through
  inspect(katakana_to_hiragana("トーキョー"), content="とーきょー")
  inspect(katakana_to_hiragana("コーヒー"), content="こーひー")
}

///|
test "katakana_to_hiragana handles mixed input" {
  inspect(katakana_to_hiragana("カタひらKanji漢字"), content="かたひらKanji漢字")
}

///|
test "load_dic_bin builds reading index" {
  clear_runtime_state()

  // Dictionary with reading in field 7
  let dic = build_test_dic_bin(
    [
      ("東京", "名詞,固有名詞,地域,一般,*,*,東京,トウキョウ,トーキョー", 1, 1, 5000),
      ("猫", "名詞,一般,*,*,*,*,猫,ネコ,ネコ", 1, 1, 3000),
    ],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let ok = load_dic_bin(dic[:])
  inspect(ok, content="true")

  // Reading index should be built (hiragana keys)
  let tokyo_entries = get_entries_by_reading("とうきょう")
  inspect(tokyo_entries.length(), content="1")

  let neko_entries = get_entries_by_reading("ねこ")
  inspect(neko_entries.length(), content="1")

  // Non-existent reading
  let none_entries = get_entries_by_reading("そんざいしない")
  inspect(none_entries.length(), content="0")
}

///|
test "merge_dic_bin updates reading index" {
  clear_runtime_state()

  // Base dictionary
  let base_dic = build_test_dic_bin(
    [("猫", "名詞,一般,*,*,*,*,猫,ネコ,ネコ", 1, 1, 3000)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let base_ok = load_dic_bin(base_dic[:])
  inspect(base_ok, content="true")
  inspect(get_entries_by_reading("ねこ").length(), content="1")

  // Additional dictionary
  let add_dic = build_test_dic_bin(
    [("犬", "名詞,一般,*,*,*,*,犬,イヌ,イヌ", 1, 1, 2000)],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let merge_ok = merge_dic_bin(add_dic[:])
  inspect(merge_ok, content="true")

  // Both readings should be indexed
  inspect(get_entries_by_reading("ねこ").length(), content="1")
  inspect(get_entries_by_reading("いぬ").length(), content="1")
}

///|
test "get_entry returns entry by index" {
  clear_runtime_state()

  let dic = build_test_dic_bin(
    [
      ("猫", "名詞,一般,*,*,*,*,猫,ネコ,ネコ", 1, 1, 3000),
      ("犬", "名詞,一般,*,*,*,*,犬,イヌ,イヌ", 1, 1, 2000),
    ],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let ok = load_dic_bin(dic[:])
  inspect(ok, content="true")

  match get_entry(0) {
    Some(e) => inspect(e.surface, content="猫")
    None => inspect(false, content="true")
  }

  match get_entry(1) {
    Some(e) => inspect(e.surface, content="犬")
    None => inspect(false, content="true")
  }

  // Out of bounds
  match get_entry(99) {
    Some(_) => inspect(false, content="true")
    None => inspect(true, content="true")
  }
}

///|
test "get_all_entries returns all entries as RuntimeEntry" {
  clear_runtime_state()

  let dic = build_test_dic_bin(
    [
      ("猫", "名詞,一般,*,*,*,*,猫,ネコ,ネコ", 1, 1, 3000),
      ("犬", "名詞,一般,*,*,*,*,犬,イヌ,イヌ", 2, 2, 2000),
    ],
    [0, 1, 2],
    [0, 100, 100, 100, 0, 100, 100, 100, 0],
    10000,
  )
  let ok = load_dic_bin(dic[:])
  inspect(ok, content="true")

  let entries = get_all_entries()
  inspect(entries.length(), content="2")
  inspect(entries[0].surface, content="猫")
  inspect(entries[0].word_cost, content="3000")
  inspect(entries[1].surface, content="犬")
  inspect(entries[1].word_cost, content="2000")
}

///|
test "get_all_readings returns all indexed readings" {
  clear_runtime_state()

  let dic = build_test_dic_bin(
    [
      ("猫", "名詞,一般,*,*,*,*,猫,ネコ,ネコ", 1, 1, 3000),
      ("犬", "名詞,一般,*,*,*,*,犬,イヌ,イヌ", 1, 1, 2000),
      ("鳥", "名詞,一般,*,*,*,*,鳥,トリ,トリ", 1, 1, 4000),
    ],
    [0, 1],
    [0, 100, 100, 0],
    10000,
  )
  let ok = load_dic_bin(dic[:])
  inspect(ok, content="true")

  let readings = get_all_readings()
  inspect(readings.length(), content="3")
  // Readings should be in hiragana
  inspect(readings.contains("ねこ"), content="true")
  inspect(readings.contains("いぬ"), content="true")
  inspect(readings.contains("とり"), content="true")
}
