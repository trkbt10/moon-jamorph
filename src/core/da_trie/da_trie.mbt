///|
type DictEntry = @types.DictEntry

///|
type TokenCandidate = @types.TokenCandidate

///|
pub struct DATrie {
  bmp_code_map : Array[Int]
  base : ReadOnlyArray[Int]
  check : ReadOnlyArray[Int]
  term_starts : ReadOnlyArray[Int]
  term_entry_indexes : ReadOnlyArray[Int]
}

///|
fn build_bmp_code_map(char_table : ReadOnlyArray[String]) -> Array[Int] {
  let map = Array::makei(0x10000, _ => 0)
  for i in 0..<char_table.length() {
    let chars = char_table[i].to_array()
    if chars.length() == 0 {
      continue
    }
    let cp = chars[0].to_int()
    if cp >= 0 && cp < map.length() {
      map[cp] = i + 1
    }
  }
  map
}

///|
pub fn from_generated_arrays(
  char_table : ReadOnlyArray[String],
  base : ReadOnlyArray[Int],
  check : ReadOnlyArray[Int],
  term_starts : ReadOnlyArray[Int],
  term_entry_indexes : ReadOnlyArray[Int],
) -> DATrie {
  {
    bmp_code_map: build_bmp_code_map(char_table),
    base,
    check,
    term_starts,
    term_entry_indexes,
  }
}

///|
fn code_for_char(bmp_code_map : Array[Int], ch : Char) -> Int {
  let cp = ch.to_int()
  if cp < 0 || cp >= bmp_code_map.length() {
    0
  } else {
    bmp_code_map[cp]
  }
}

///|
pub fn append_common_prefix_search(
  dst : Array[TokenCandidate],
  chars : Array[Char],
  start : Int,
  entries : ReadOnlyArray[DictEntry],
  trie : DATrie,
) -> Unit {
  if trie.base.length() <= 1 || start >= chars.length() {
    return
  }
  let mut node = 1
  for i in start..<chars.length() {
    let code = code_for_char(trie.bmp_code_map, chars[i])
    if code == 0 {
      break
    }
    let next = trie.base[node] + code
    if next < 0 || next >= trie.check.length() || trie.check[next] != node {
      break
    }
    node = next
    let from = trie.term_starts[node]
    let to = trie.term_starts[node + 1]
    for j in from..<to {
      let entry = entries[trie.term_entry_indexes[j]]
      dst.push({
        start_pos: start,
        end_pos: i + 1,
        pos: entry.pos,
        pos_detail: entry.pos_detail,
        mecab_feature: entry.mecab_feature,
        left_id: entry.left_id,
        right_id: entry.right_id,
        word_cost: entry.word_cost,
      })
    }
  }
}

///|
pub fn common_prefix_search(
  chars : Array[Char],
  start : Int,
  entries : ReadOnlyArray[DictEntry],
  trie : DATrie,
) -> Array[TokenCandidate] {
  let results : Array[TokenCandidate] = Array::new(capacity=8)
  append_common_prefix_search(results, chars, start, entries, trie)
  results
}
