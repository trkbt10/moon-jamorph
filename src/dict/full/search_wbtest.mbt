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
test "neologd da trie search should find known hashtag word" {
  let cands = common_prefix_search_neologd("#AirPodsを買う".to_array(), 0)
  inspect(cands.length() > 0, content="true")
  inspect(has_pos_detail(cands, "名詞,固有名詞,一般,*"), content="true")
  inspect(has_start_end(cands, 0, 8), content="true")
}

///|
test "neologd da trie search should find known punctuation word" {
  let cands = common_prefix_search_neologd("!Wagero!".to_array(), 0)
  inspect(cands.length() > 0, content="true")
  inspect(
    has_pos_detail(cands, "名詞,固有名詞,人名,一般"),
    content="true",
  )
}

///|
test "neologd da trie search should return empty for unknown head" {
  let cands = common_prefix_search_neologd("~airpods".to_array(), 0)
  inspect(cands.is_empty(), content="true")
}
