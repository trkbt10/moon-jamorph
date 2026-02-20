///|
fn is_ascii_punctuation(cp : Int) -> Bool {
  (cp >= 0x21 && cp <= 0x2F) ||
  (cp >= 0x3A && cp <= 0x40) ||
  (cp >= 0x5B && cp <= 0x60) ||
  (cp >= 0x7B && cp <= 0x7E)
}

///|
fn classify_code_point(cp : Int) -> @types.CharClass {
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
  } else if cp <= 0x7F && is_ascii_punctuation(cp) {
    @types.CharClass::Symbol
  } else {
    @types.CharClass::Other
  }
}

///|
fn decode_next_utf8_code_point(bytes : BytesView, pos : Int) -> (Int, Int) {
  let b0 = bytes[pos].to_int()
  if b0 <= 0x7F {
    return (b0, 1)
  }
  if (b0 & 0xE0) == 0xC0 && pos + 1 < bytes.length() {
    let b1 = bytes[pos + 1].to_int()
    if (b1 & 0xC0) == 0x80 {
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      if cp >= 0x80 {
        return (cp, 2)
      }
    }
    return (0xFFFD, 1)
  }
  if (b0 & 0xF0) == 0xE0 && pos + 2 < bytes.length() {
    let b1 = bytes[pos + 1].to_int()
    let b2 = bytes[pos + 2].to_int()
    if (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80 {
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp >= 0x800 {
        return (cp, 3)
      }
    }
    return (0xFFFD, 1)
  }
  if (b0 & 0xF8) == 0xF0 && pos + 3 < bytes.length() {
    let b1 = bytes[pos + 1].to_int()
    let b2 = bytes[pos + 2].to_int()
    let b3 = bytes[pos + 3].to_int()
    if (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80 && (b3 & 0xC0) == 0x80 {
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp >= 0x10000 && cp <= 0x10FFFF {
        return (cp, 4)
      }
    }
    return (0xFFFD, 1)
  }
  (0xFFFD, 1)
}

///|
pub fn scan_char_classes_manual_utf8(
  input : BytesView,
) -> Array[@types.CharClass] {
  let classes : Array[@types.CharClass] = Array::new(capacity=input.length())
  let mut pos = 0
  while pos < input.length() {
    let (cp, width) = decode_next_utf8_code_point(input, pos)
    classes.push(classify_code_point(cp))
    pos = pos + width
  }
  classes
}

///|
pub fn scan_char_classes_lexmatch_utf8(
  input : BytesView,
) -> Array[@types.CharClass] {
  // UTF-8 bytes -> String に変換し、1文字ごと lexmatch 判定を使う。
  let text = @enc8.decode_lossy(input)
  let classes = Array::new(capacity=text.char_length())
  for ch in text.iter() {
    let sv = ch.to_string()[:]
    let class = lexmatch sv with longest {
      ("[ぁ-ゟ]+", _) => @types.CharClass::Hiragana
      ("[ァ-ヿー]+", _) => @types.CharClass::Katakana
      ("[㐀-䶿一-鿿]+", _) => @types.CharClass::Kanji
      ("[a-zA-Z]+", _) => @types.CharClass::AsciiAlpha
      ("[0-9]+", _) => @types.CharClass::AsciiDigit
      ("[!-~]+", _) => @types.CharClass::Symbol
      _ => @types.CharClass::Other
    }
    classes.push(class)
  }
  classes
}

///|
pub fn scanner_modes_match_utf8(input : BytesView) -> Bool {
  scan_char_classes_manual_utf8(input) == scan_char_classes_lexmatch_utf8(input)
}
