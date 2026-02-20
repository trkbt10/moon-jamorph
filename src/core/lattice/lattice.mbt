///|
type TokenCandidate = @types.TokenCandidate

///|
fn append_dict_candidates(
  dst : Array[TokenCandidate],
  chars : Array[Char],
  pos : Int,
  edition : Int,
) -> Unit {
  @nano.append_common_prefix_search_nano(dst, chars, pos)
  if edition == 1 || edition == 2 || edition == 3 {
    @mini.append_common_prefix_search_mini_extra(dst, chars, pos)
  }
  if edition == 2 || edition == 3 {
    @standard.append_common_prefix_search_standard_extra(dst, chars, pos)
    @standard.append_common_prefix_search_ipadic(dst, chars, pos)
  }
  if edition == 3 {
    @full.append_common_prefix_search_neologd(dst, chars, pos)
  }
}

///|
pub fn candidates_at_into(
  dst : Array[@types.TokenCandidate],
  chars : Array[Char],
  classes : Array[@types.CharClass],
  pos : Int,
  edition : Int,
) -> Unit {
  dst.truncate(0)
  append_dict_candidates(dst, chars, pos, edition)
  if dst.is_empty() {
    @unknown.append_unknown_candidates(dst, classes, pos)
  }
}

///|
pub fn candidates_at(
  chars : Array[Char],
  classes : Array[@types.CharClass],
  pos : Int,
  edition : Int,
) -> Array[@types.TokenCandidate] {
  let results : Array[@types.TokenCandidate] = Array::new(capacity=12)
  candidates_at_into(results, chars, classes, pos, edition)
  results
}
