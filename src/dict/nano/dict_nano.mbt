///|
type DictEntry = @types.DictEntry

///|
type POS = @types.POS

///|
type TokenCandidate = @types.TokenCandidate

///|
let nano_entries : ReadOnlyArray[DictEntry] = [
  {
    surface: "すもも",
    pos: POS::NounGeneral,
    pos_detail: "名詞,一般,*,*",
    mecab_feature: "名詞,一般,*,*,*,*,すもも,スモモ,スモモ",
    left_id: 1,
    right_id: 1,
    word_cost: 1200,
  },
  {
    surface: "も",
    pos: POS::Particle,
    pos_detail: "助詞,係助詞,*,*",
    mecab_feature: "助詞,係助詞,*,*,*,*,も,モ,モ",
    left_id: 2,
    right_id: 2,
    word_cost: 150,
  },
  {
    surface: "もも",
    pos: POS::NounGeneral,
    pos_detail: "名詞,一般,*,*",
    mecab_feature: "名詞,一般,*,*,*,*,もも,モモ,モモ",
    left_id: 1,
    right_id: 1,
    word_cost: 900,
  },
  {
    surface: "の",
    pos: POS::Particle,
    pos_detail: "助詞,連体化,*,*",
    mecab_feature: "助詞,連体化,*,*,*,*,の,ノ,ノ",
    left_id: 2,
    right_id: 2,
    word_cost: 120,
  },
  {
    surface: "うち",
    pos: POS::NounNonIndependent,
    pos_detail: "名詞,非自立,副詞可能,*",
    mecab_feature: "名詞,非自立,副詞可能,*,*,*,うち,ウチ,ウチ",
    left_id: 1,
    right_id: 1,
    word_cost: 800,
  },
]

///|
let da_base : ReadOnlyArray[Int] = [0, 1, 4, 6, 0, 4, 5, 0, 0, 0]

///|
let da_check : ReadOnlyArray[Int] = [-1, -1, 1, 1, 1, 1, 2, 6, 3, 5]

///|
let da_term : ReadOnlyArray[UInt] = [920U]

///|
let da_term_entry_index : ReadOnlyArray[Int] = [
  -1, -1, -1, 1, 3, -1, -1, 0, 2, 4,
]

///|
fn transition_key_utf16(ch : Char) -> Int {
  match ch {
    'す' => 1
    'も' => 2
    'の' => 3
    'う' => 4
    'ち' => 5
    _ => 0
  }
}

///|
fn trie_is_terminal(node : Int) -> Bool {
  let bits = da_term[node / 32].reinterpret_as_int()
  ((bits >> (node % 32)) & 1) == 1
}

///|
fn trie_entry_for_node(node : Int) -> DictEntry? {
  if !trie_is_terminal(node) {
    return None
  }
  let entry_index = da_term_entry_index[node]
  if entry_index < 0 {
    None
  } else {
    Some(nano_entries[entry_index])
  }
}

///|
pub fn append_common_prefix_search_nano(
  dst : Array[TokenCandidate],
  chars : Array[Char],
  start : Int,
) -> Unit {
  let mut node = 1
  for i in start..<chars.length() {
    let key = transition_key_utf16(chars[i])
    if key == 0 {
      break
    }
    let next = da_base[node] + key
    if next < 0 || next >= da_check.length() || da_check[next] != node {
      break
    }
    node = next
    match trie_entry_for_node(node) {
      Some(entry) =>
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
      None => ()
    }
  }
}

///|
pub fn common_prefix_search_nano(
  chars : Array[Char],
  start : Int,
) -> Array[TokenCandidate] {
  let results : Array[TokenCandidate] = Array::new(capacity=4)
  append_common_prefix_search_nano(results, chars, start)
  results
}
