///|
type DictEntry = @types.DictEntry

///|
type POS = @types.POS

///|
type TokenCandidate = @types.TokenCandidate

///|
let mini_extra_entries : ReadOnlyArray[DictEntry] = [
  {
    surface: "東京",
    pos: POS::NounProper,
    pos_detail: "名詞,固有名詞,地域,一般",
    left_id: 1,
    right_id: 1,
    word_cost: 650,
  },
  {
    surface: "大学",
    pos: POS::NounGeneral,
    pos_detail: "名詞,一般,*,*",
    left_id: 1,
    right_id: 1,
    word_cost: 700,
  },
  {
    surface: "学生",
    pos: POS::NounGeneral,
    pos_detail: "名詞,一般,*,*",
    left_id: 1,
    right_id: 1,
    word_cost: 750,
  },
]

///|
let mini_extra_bucket_keys : ReadOnlyArray[String] = ["東", "大", "学"]

///|
let mini_extra_bucket_starts : ReadOnlyArray[Int] = [0, 1, 2, 3]

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
pub fn append_common_prefix_search_mini_extra(
  dst : Array[TokenCandidate],
  chars : Array[Char],
  start : Int,
) -> Unit {
  if start >= chars.length() {
    return
  }
  let head = chars[start].to_string()
  let (from, to) = bucket_range_for_head(
    head, mini_extra_bucket_keys, mini_extra_bucket_starts,
  )
  if from >= to {
    return
  }
  for i in from..<to {
    let entry = mini_extra_entries[i]
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
pub fn common_prefix_search_mini_extra(
  chars : Array[Char],
  start : Int,
) -> Array[TokenCandidate] {
  let results : Array[TokenCandidate] = Array::new(capacity=4)
  append_common_prefix_search_mini_extra(results, chars, start)
  results
}
