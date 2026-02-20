///|
fn has_pos_detail(
  cands : Array[@types.TokenCandidate],
  detail : String,
) -> Bool {
  for c in cands {
    if c.pos_detail == detail {
      return true
    }
  }
  false
}

///|
fn has_start_end(
  cands : Array[@types.TokenCandidate],
  start : Int,
  end_ : Int,
) -> Bool {
  for c in cands {
    if c.start_pos == start && c.end_pos == end_ {
      return true
    }
  }
  false
}

///|
test "ipadic da trie search should find known word" {
  let cands = common_prefix_search_ipadic("迅速な".to_array(), 0)
  inspect(cands.length() > 0, content="true")
  inspect(
    has_pos_detail(cands, "名詞,形容動詞語幹,*,*"),
    content="true",
  )
  inspect(has_start_end(cands, 0, 2), content="true")
}

///|
test "ipadic da trie search should respect start offset" {
  let cands = common_prefix_search_ipadic("X迅速な".to_array(), 1)
  inspect(cands.length() > 0, content="true")
  inspect(has_start_end(cands, 1, 3), content="true")
}

///|
test "ipadic da trie search should return empty for unknown head" {
  let cands = common_prefix_search_ipadic("@@@".to_array(), 0)
  inspect(cands.is_empty(), content="true")
}

///|
test "standard extra search should find tokyo metropolitan" {
  let cands = common_prefix_search_standard_extra(
    "東京都大学院".to_array(),
    0,
  )
  inspect(cands.length() > 0, content="true")
  inspect(has_start_end(cands, 0, 3), content="true")
}

///|
test "standard extra search should return empty for unknown head" {
  let cands = common_prefix_search_standard_extra("迅速".to_array(), 0)
  inspect(cands.is_empty(), content="true")
}
