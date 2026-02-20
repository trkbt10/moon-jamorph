///|
pub(all) enum CharClass {
  Hiragana
  Katakana
  Kanji
  AsciiAlpha
  AsciiDigit
  Symbol
  Other
} derive(Eq, Show)

///|
pub(all) enum POS {
  BosEos
  NounGeneral
  NounProper
  NounNonIndependent
  Particle
  Unknown
} derive(Eq, Show)

///|
pub fn POS::label(self : POS) -> String {
  match self {
    POS::BosEos => "BOS/EOS"
    POS::NounGeneral => "名詞,一般"
    POS::NounProper => "名詞,固有名詞"
    POS::NounNonIndependent => "名詞,非自立"
    POS::Particle => "助詞"
    POS::Unknown => "未知語"
  }
}

///|
pub(all) struct DictEntry {
  surface : String
  pos : POS
  pos_detail : String
  mecab_feature : String
  left_id : Int
  right_id : Int
  word_cost : Int
}

///|
pub(all) struct TokenCandidate {
  start_pos : Int
  end_pos : Int
  pos : POS
  pos_detail : String
  mecab_feature : String
  left_id : Int
  right_id : Int
  word_cost : Int
}

///|
pub(all) struct LatticeNode {
  start_pos : Int
  end_pos : Int
  pos : POS
  pos_detail_id : Int
  mecab_feature_id : Int
  right_id : Int
  right_compact_id : Int
  best_cost : Int
  best_prev : Int
}

///|
pub(all) struct Morpheme {
  surface : String
  pos : POS
  pos_detail : String
  mecab_feature : String
  start_pos : Int
  end_pos : Int
}

///|
pub fn chars_slice(chars : Array[Char], start : Int, end : Int) -> String {
  let b = StringBuilder::new(size_hint=end - start)
  for i in start..<end {
    b.write_char(chars[i])
  }
  b.to_string()
}
