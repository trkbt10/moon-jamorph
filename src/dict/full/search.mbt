///|
type Candidate = @types.TokenCandidate

///|
type DATrie = @datrie.DATrie

///|
let neologd_da_trie : DATrie = @datrie.from_generated_arrays(
  neologd_da_char_table, neologd_da_base, neologd_da_check, neologd_da_term_starts,
  neologd_da_term_entry_indexes,
)

///|
pub fn append_common_prefix_search_neologd(
  dst : Array[Candidate],
  chars : Array[Char],
  start : Int,
) -> Unit {
  @datrie.append_common_prefix_search(
    dst, chars, start, neologd_entries_generated, neologd_da_trie,
  )
}

///|
pub fn common_prefix_search_neologd(
  chars : Array[Char],
  start : Int,
) -> Array[Candidate] {
  let results : Array[Candidate] = Array::new(capacity=8)
  append_common_prefix_search_neologd(results, chars, start)
  results
}
