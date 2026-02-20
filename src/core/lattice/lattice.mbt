///|
type TokenCandidate = @types.TokenCandidate

///|
fn append_dict_candidates(
  dst : Array[TokenCandidate],
  chars : Array[Char],
  pos : Int,
  edition : Int,
) -> Unit {
  match edition {
    0 => @nano.append_common_prefix_search_nano(dst, chars, pos)
    1 => {
      @nano.append_common_prefix_search_nano(dst, chars, pos)
      @mini.append_common_prefix_search_mini_extra(dst, chars, pos)
    }
    2 => {
      @nano.append_common_prefix_search_nano(dst, chars, pos)
      @mini.append_common_prefix_search_mini_extra(dst, chars, pos)
      @standard.append_common_prefix_search_standard_extra(dst, chars, pos)
      @standard.append_common_prefix_search_ipadic(dst, chars, pos)
    }
    _ => {
      @nano.append_common_prefix_search_nano(dst, chars, pos)
      @mini.append_common_prefix_search_mini_extra(dst, chars, pos)
      @standard.append_common_prefix_search_standard_extra(dst, chars, pos)
      @standard.append_common_prefix_search_ipadic(dst, chars, pos)
      @full.append_common_prefix_search_neologd(dst, chars, pos)
    }
  }
}

///|
pub fn candidates_at_into_with_run_lengths(
  dst : Array[@types.TokenCandidate],
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
  pos : Int,
  edition : Int,
) -> Unit {
  dst.truncate(0)
  append_dict_candidates(dst, chars, pos, edition)
  if dst.is_empty() {
    if run_lengths.length() == classes.length() {
      let run_len = run_lengths[pos]
      @unknown.append_unknown_candidates_with_run_len(
        dst, classes, pos, run_len,
      )
    } else {
      @unknown.append_unknown_candidates(dst, classes, pos)
    }
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
  candidates_at_into_with_run_lengths(dst, chars, classes, [], pos, edition)
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
