///|
pub fn classify_manual(ch : Char) -> @types.CharClass {
  let cp = ch.to_int()
  if cp >= 0x3041 && cp <= 0x309F {
    @types.CharClass::Hiragana
  } else if cp >= 0x30A1 && cp <= 0x30FF {
    @types.CharClass::Katakana
  } else if (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0x3400 && cp <= 0x4DBF) {
    @types.CharClass::Kanji
  } else if (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A) {
    @types.CharClass::AsciiAlpha
  } else if cp >= 0x30 && cp <= 0x39 {
    @types.CharClass::AsciiDigit
  } else if ch.is_ascii_punctuation() {
    @types.CharClass::Symbol
  } else {
    @types.CharClass::Other
  }
}

///|
pub fn classify_lexmatch(ch : Char) -> @types.CharClass {
  let sv = ch.to_string()[:]
  lexmatch sv with longest {
    ("[ぁ-ゟ]+", _) => @types.CharClass::Hiragana
    ("[ァ-ヿー]+", _) => @types.CharClass::Katakana
    ("[㐀-䶿一-鿿]+", _) => @types.CharClass::Kanji
    ("[a-zA-Z]+", _) => @types.CharClass::AsciiAlpha
    ("[0-9]+", _) => @types.CharClass::AsciiDigit
    ("[!-~]+", _) => @types.CharClass::Symbol
    _ => @types.CharClass::Other
  }
}

///|
pub fn scan_char_classes_manual(input : String) -> Array[@types.CharClass] {
  let classes = Array::new(capacity=input.char_length())
  for ch in input.iter() {
    classes.push(classify_manual(ch))
  }
  classes
}

///|
pub fn scan_char_classes_lexmatch(input : String) -> Array[@types.CharClass] {
  let classes = Array::new(capacity=input.char_length())
  for ch in input.iter() {
    classes.push(classify_lexmatch(ch))
  }
  classes
}

///|
pub fn scanner_modes_match(input : String) -> Bool {
  scan_char_classes_manual(input) == scan_char_classes_lexmatch(input)
}
