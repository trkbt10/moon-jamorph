///|
type POS = @types.POS

///|
fn test_entry(surface : String, pos : POS) -> @types.DictEntry {
  { surface, pos, pos_detail: "x", left_id: 1, right_id: 1, word_cost: 1 }
}

///|
test "da trie common_prefix_search should return prefix entries" {
  let entries : ReadOnlyArray[@types.DictEntry] = [
    test_entry("東京", POS::NounProper),
    test_entry("東京都", POS::NounProper),
  ]
  let trie = from_generated_arrays(
    ["東", "京", "都"],
    [-1, 1, 2, -1, 2, 0],
    [-1, 0, 1, -1, 2, 4],
    [0, 0, 0, 0, 0, 1, 2],
    [0, 1],
  )
  let hits = common_prefix_search("東京都".to_array(), 0, entries, trie)
  inspect(hits.length(), content="2")
  inspect(hits.map(h => h.end_pos), content="[2, 3]")
}
