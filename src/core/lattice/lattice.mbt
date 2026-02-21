///|
pub fn candidates_at_into_with_run_lengths(
  dst : Array[@types.TokenCandidate],
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
  pos : Int,
  edition : Int,
) -> Unit {
  let _ = chars
  let _ = edition
  dst.truncate(0)
  if run_lengths.length() == classes.length() {
    let run_len = run_lengths[pos]
    @unknown.append_unknown_candidates_with_run_len(dst, classes, pos, run_len)
  } else {
    @unknown.append_unknown_candidates(dst, classes, pos)
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
