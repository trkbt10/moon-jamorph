///|
test "parse_tsv_lexicon should parse rows" {
  let tsv = "# surface\tpos\tleft\tright\tcost\n東京\tNOUN_PROPER\t1\t1\t600\n大学\tNOUN_GENERAL\t1\t1\t700\n"
  let rows = parse_tsv_lexicon(tsv)
  inspect(rows.length(), content="2")
  inspect(rows[0].surface, content="東京")
  inspect(rows[1].word_cost, content="700")
}

///|
test "compile_tsv_to_entries_module should emit moonbit snippet" {
  let tsv = "東京\tNOUN_PROPER\t1\t1\t600\n"
  let generated = compile_tsv_to_entries_module(tsv, "mini_extra_entries")
  inspect(generated.find("mini_extra_entries") is Some(_), content="true")
  inspect(generated.find("surface: \"東京\"") is Some(_), content="true")
  inspect(generated.find("POS::NounProper") is Some(_), content="true")
  inspect(generated.find("distinct_first_chars: 1") is Some(_), content="true")
}

///|
test "compile_tsv_to_entries_module_for_edition should filter by edition" {
  let tsv = "東京\tNOUN_PROPER\t1\t1\t600\nも\tPARTICLE\t2\t2\t100\n"
  let nano = compile_tsv_to_entries_module_for_edition(
    tsv, "nano_entries", "nano",
  )
  inspect(nano.find("surface: \"東京\"") is None, content="true")
  inspect(nano.find("surface: \"も\"") is Some(_), content="true")
}

///|
test "build_compact_id_mapping should emit compact id array" {
  let rows : Array[LexiconRow] = [
    {
      surface: "a",
      pos_tag: "NOUN_GENERAL",
      left_id: 2,
      right_id: 2,
      word_cost: 1,
    },
    {
      surface: "b",
      pos_tag: "NOUN_GENERAL",
      left_id: 10,
      right_id: 5,
      word_cost: 1,
    },
  ]
  let mapping = build_compact_id_mapping(rows, 10)
  inspect(mapping[2], content="0")
  inspect(mapping[10], content="1")
  inspect(mapping[5], content="2")
}

///|
test "compile_tsv_to_da_trie_module_for_edition should emit trie arrays" {
  let tsv = "東京\tNOUN_PROPER\t1\t1\t600\n東京\tNOUN_PROPER\t1\t1\t650\n大学\tNOUN_GENERAL\t2\t2\t700\n"
  let generated = compile_tsv_to_da_trie_module_for_edition(
    tsv, "mini_trie", "mini",
  )
  inspect(generated.find("mini_trie_char_table") is Some(_), content="true")
  inspect(generated.find("mini_trie_base") is Some(_), content="true")
  inspect(generated.find("mini_trie_check") is Some(_), content="true")
  inspect(
    generated.find("mini_trie_term_entry_indexes") is Some(_),
    content="true",
  )
}
