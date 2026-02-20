///|
pub(all) struct LexiconRow {
  surface : String
  pos_tag : String
  left_id : Int
  right_id : Int
  word_cost : Int
}

///|
fn is_row_supported(row : LexiconRow, edition : String) -> Bool {
  @editions.should_include_pos_tag(row.pos_tag, edition)
}

///|
fn filter_rows_for_edition(
  rows : Array[LexiconRow],
  edition : String,
) -> Array[LexiconRow] {
  let filtered = Array::new()
  for row in rows {
    if is_row_supported(row, edition) {
      filtered.push(row)
    }
  }
  filtered
}

///|
fn collect_ids(rows : Array[LexiconRow]) -> Array[Int] {
  let ids = Array::new(capacity=rows.length() * 2)
  for row in rows {
    ids.push(row.left_id)
    ids.push(row.right_id)
  }
  ids
}

///|
fn parse_int_relaxed(text : String) -> Int {
  if text.length() == 0 {
    return 0
  }
  let mut idx = 0
  let mut sign = 1
  match text[:] {
    ['-', ..] => {
      sign = -1
      idx = 1
    }
    _ => ()
  }
  let mut value = 0
  while idx < text.length() {
    let code = text.unsafe_get(idx).to_int()
    if code < 0x30 || code > 0x39 {
      idx = text.length()
    } else {
      value = value * 10 + (code - 0x30)
      idx = idx + 1
    }
  }
  value * sign
}

///|
fn parse_tsv_line(line : String) -> LexiconRow? {
  let cols = line.split("\t").map(StringView::to_string).collect()
  if cols.length() < 5 {
    return None
  }
  Some({
    surface: cols[0],
    pos_tag: cols[1],
    left_id: parse_int_relaxed(cols[2]),
    right_id: parse_int_relaxed(cols[3]),
    word_cost: parse_int_relaxed(cols[4]),
  })
}

///|
pub fn parse_tsv_lexicon(tsv : String) -> Array[LexiconRow] {
  let rows = Array::new()
  for line in tsv.split("\n").map(StringView::to_string) {
    let normalized = line.replace_all(old="\r", new="")
    if normalized.length() == 0 {
      continue
    }
    // Keep hashtag surfaces like "#AirPods"; only "# " prefixed lines are comments.
    if normalized.length() >= 2 &&
      normalized.unsafe_get(0) == '#' &&
      normalized.unsafe_get(1) == ' ' {
      continue
    }
    match parse_tsv_line(normalized) {
      Some(row) => rows.push(row)
      None => ()
    }
  }
  rows
}

///|
fn escape_mbt_string(input : String) -> String {
  input.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
fn write_int_array_literal(
  b : StringBuilder,
  symbol_name : String,
  xs : Array[Int],
) -> Unit {
  b.write_string("///|\n")
  b.write_string("let ")
  b.write_string(symbol_name)
  b.write_string(" : ReadOnlyArray[Int] = [")
  if xs.length() > 0 {
    b.write_string("\n")
    for x in xs {
      b.write_string("  ")
      b.write_string(x.to_string())
      b.write_string(",\n")
    }
  }
  b.write_string("]\n")
}

///|
fn write_string_array_literal(
  b : StringBuilder,
  symbol_name : String,
  xs : Array[String],
) -> Unit {
  b.write_string("///|\n")
  b.write_string("let ")
  b.write_string(symbol_name)
  b.write_string(" : ReadOnlyArray[String] = [")
  if xs.length() > 0 {
    b.write_string("\n")
    for x in xs {
      b.write_string("  \"")
      b.write_string(escape_mbt_string(x))
      b.write_string("\",\n")
    }
  }
  b.write_string("]\n")
}

///|
fn pos_expr_from_tag(pos_tag : String) -> String {
  match pos_tag {
    "NOUN_GENERAL" | "名詞,一般" => "POS::NounGeneral"
    "NOUN_PROPER" | "名詞,固有名詞" => "POS::NounProper"
    "NOUN_NON_INDEPENDENT" | "名詞,非自立" => "POS::NounNonIndependent"
    "PARTICLE" | "助詞" => "POS::Particle"
    _ => "POS::Unknown"
  }
}

///|
pub fn emit_extra_entries_module(
  symbol_name : String,
  rows : Array[LexiconRow],
) -> String {
  let surfaces = rows.map(r => r.surface)
  let first_chars = @builder.first_char_count(surfaces)
  let b = StringBuilder::new()
  b.write_string("///|\n")
  b.write_string("/// distinct_first_chars: ")
  b.write_string(first_chars.to_string())
  b.write_string("\n")
  b.write_string("///|\n")
  b.write_string("let ")
  b.write_string(symbol_name)
  b.write_string(" : ReadOnlyArray[DictEntry] = [\n")
  for row in rows {
    b.write_string("  {\n")
    b.write_string("    surface: \"")
    b.write_string(escape_mbt_string(row.surface))
    b.write_string("\",\n")
    b.write_string("    pos: ")
    b.write_string(pos_expr_from_tag(row.pos_tag))
    b.write_string(",\n")
    b.write_string("    left_id: ")
    b.write_string(row.left_id.to_string())
    b.write_string(",\n")
    b.write_string("    right_id: ")
    b.write_string(row.right_id.to_string())
    b.write_string(",\n")
    b.write_string("    word_cost: ")
    b.write_string(row.word_cost.to_string())
    b.write_string(",\n")
    b.write_string("  },\n")
  }
  b.write_string("]\n")
  b.to_string()
}

///|
pub fn compile_tsv_to_entries_module(
  tsv : String,
  symbol_name : String,
) -> String {
  compile_tsv_to_entries_module_for_edition(
    tsv,
    symbol_name,
    @editions.EDITION_STANDARD,
  )
}

///|
pub fn compile_tsv_to_entries_module_for_edition(
  tsv : String,
  symbol_name : String,
  edition : String,
) -> String {
  let rows = parse_tsv_lexicon(tsv)
  let filtered = filter_rows_for_edition(rows, edition)
  emit_extra_entries_module(symbol_name, filtered)
}

///|
pub fn build_compact_id_mapping(
  rows : Array[LexiconRow],
  max_id : Int,
) -> Array[Int] {
  let ids = collect_ids(rows)
  let unique_ids = @compressor.compact_ids_preserve_order(ids)
  @compressor.build_id_to_compact(unique_ids, max_id)
}

///|
pub fn emit_da_trie_module(
  symbol_prefix : String,
  surfaces : Array[String],
) -> String {
  let trie = @builder.build_da_trie_from_surfaces(surfaces)
  let char_table = trie.char_table.map(c => c.to_string())
  let b = StringBuilder::new()
  b.write_string("///|\n")
  b.write_string("/// DA-Trie generated by dict-compiler\n")
  write_string_array_literal(b, symbol_prefix + "_char_table", char_table)
  b.write_string("\n")
  write_int_array_literal(b, symbol_prefix + "_base", trie.base)
  b.write_string("\n")
  write_int_array_literal(b, symbol_prefix + "_check", trie.check)
  b.write_string("\n")
  write_int_array_literal(b, symbol_prefix + "_term_starts", trie.term_starts)
  b.write_string("\n")
  write_int_array_literal(
    b,
    symbol_prefix + "_term_entry_indexes",
    trie.term_entry_indexes,
  )
  b.to_string()
}

///|
pub fn compile_tsv_to_da_trie_module_for_edition(
  tsv : String,
  symbol_prefix : String,
  edition : String,
) -> String {
  let rows = parse_tsv_lexicon(tsv)
  let filtered = filter_rows_for_edition(rows, edition)
  let surfaces = filtered.map(r => r.surface)
  emit_da_trie_module(symbol_prefix, surfaces)
}
