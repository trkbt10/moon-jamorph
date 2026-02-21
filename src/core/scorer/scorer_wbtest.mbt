///|
test "emission_adjustment should prefer short hiragana unknown tokens" {
  let p1 = emission_adjustment(
    @types.POS::Unknown,
    @types.CharClass::Hiragana,
    1,
    4,
  )
  let p2 = emission_adjustment(
    @types.POS::Unknown,
    @types.CharClass::Hiragana,
    2,
    4,
  )
  inspect(p1, content="-200")
  inspect(p2 > p1, content="true")
}

///|
test "emission_adjustment should prefer medium kanji spans" {
  let p1 = emission_adjustment(
    @types.POS::NounGeneral,
    @types.CharClass::Kanji,
    1,
    4,
  )
  let p2 = emission_adjustment(
    @types.POS::NounGeneral,
    @types.CharClass::Kanji,
    2,
    4,
  )
  let p4 = emission_adjustment(
    @types.POS::NounGeneral,
    @types.CharClass::Kanji,
    4,
    4,
  )
  inspect(p2 < p1, content="true")
  inspect(p4 > p2, content="true")
}

///|
test "emission_adjustment should prefer full ascii runs" {
  let full = emission_adjustment(
    @types.POS::NounProper,
    @types.CharClass::AsciiAlpha,
    4,
    4,
  )
  let split = emission_adjustment(
    @types.POS::NounProper,
    @types.CharClass::AsciiAlpha,
    1,
    4,
  )
  let unk = emission_adjustment(
    @types.POS::Unknown,
    @types.CharClass::AsciiAlpha,
    1,
    4,
  )
  inspect(full < split, content="true")
  inspect(unk > split, content="true")
}
