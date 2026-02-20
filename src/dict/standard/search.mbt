///|
type Candidate = @types.TokenCandidate

///|
type DATrie = @datrie.DATrie

///|
let standard_extra_bucket_keys : ReadOnlyArray[String] = ["東", "大", "自"]

///|
let standard_extra_bucket_starts : ReadOnlyArray[Int] = [0, 1, 2, 3]

///|
fn bucket_range_for_head(
  head : String,
  keys : ReadOnlyArray[String],
  starts : ReadOnlyArray[Int],
) -> (Int, Int) {
  for i in 0..<keys.length() {
    if keys[i] == head {
      return (starts[i], starts[i + 1])
    }
  }
  (0, 0)
}

///|
fn prefix_match(chars : Array[Char], start : Int, surface : String) -> Bool {
  let target = surface.to_array()
  if start + target.length() > chars.length() {
    return false
  }
  for i in 0..<target.length() {
    if chars[start + i] != target[i] {
      return false
    }
  }
  true
}

///|
pub fn append_common_prefix_search_standard_extra(
  dst : Array[Candidate],
  chars : Array[Char],
  start : Int,
) -> Unit {
  if start >= chars.length() {
    return
  }
  let head = chars[start].to_string()
  let (from, to) = bucket_range_for_head(
    head, standard_extra_bucket_keys, standard_extra_bucket_starts,
  )
  if from >= to {
    return
  }
  for i in from..<to {
    let entry = standard_extra_entries[i]
    if prefix_match(chars, start, entry.surface) {
      let end_pos = start + entry.surface.char_length()
      dst.push({
        start_pos: start,
        end_pos,
        pos: entry.pos,
        pos_detail: entry.pos_detail,
        left_id: entry.left_id,
        right_id: entry.right_id,
        word_cost: entry.word_cost,
      })
    }
  }
}

///|
pub fn common_prefix_search_standard_extra(
  chars : Array[Char],
  start : Int,
) -> Array[Candidate] {
  let results : Array[Candidate] = Array::new(capacity=4)
  append_common_prefix_search_standard_extra(results, chars, start)
  results
}

///|
let ipadic_da_trie : DATrie = @datrie.from_generated_arrays(
  ipadic_da_char_table, ipadic_da_base, ipadic_da_check, ipadic_da_term_starts, ipadic_da_term_entry_indexes,
)

///|
pub fn append_common_prefix_search_ipadic(
  dst : Array[Candidate],
  chars : Array[Char],
  start : Int,
) -> Unit {
  @datrie.append_common_prefix_search(
    dst, chars, start, ipadic_entries_generated, ipadic_da_trie,
  )
}

///|
pub fn common_prefix_search_ipadic(
  chars : Array[Char],
  start : Int,
) -> Array[Candidate] {
  let results : Array[Candidate] = Array::new(capacity=8)
  append_common_prefix_search_ipadic(results, chars, start)
  results
}
