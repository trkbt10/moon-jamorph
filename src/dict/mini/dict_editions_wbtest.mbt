///|
test "mini extra search should use head bucket and find Tokyo" {
  let cands = common_prefix_search_mini_extra("東京大学".to_array(), 0)
  inspect(cands.length() > 0, content="true")
  inspect(cands[0].start_pos, content="0")
}

///|
test "mini extra search should return empty on unknown head" {
  let cands = common_prefix_search_mini_extra("迅速".to_array(), 0)
  inspect(cands.is_empty(), content="true")
}
