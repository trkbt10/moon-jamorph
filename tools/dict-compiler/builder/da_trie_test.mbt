///|
test "build_da_trie_from_surfaces should find sumomo prefixes" {
  let surfaces = ["すもも", "も", "もも", "の", "うち"]
  let trie = build_da_trie_from_surfaces(surfaces)
  inspect(
    common_prefix_entry_indexes(trie, "すももも".to_array(), 0),
    content="[0]",
  )
  inspect(
    common_prefix_entry_indexes(trie, "すももも".to_array(), 2),
    content="[1, 2]",
  )
}

///|
test "build_da_trie_from_surfaces should preserve duplicate terminal entries" {
  let surfaces = ["東京", "東京", "東京都", "大学"]
  let trie = build_da_trie_from_surfaces(surfaces)
  inspect(
    common_prefix_entry_indexes(trie, "東京都".to_array(), 0),
    content="[0, 1, 2]",
  )
}
