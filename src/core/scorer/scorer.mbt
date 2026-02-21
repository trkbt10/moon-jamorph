///|
pub fn connection_cost(right_id : Int, left_id : Int) -> Int {
  @runtime.connection_cost_by_index(right_id, left_id)
}

///|
pub fn connection_index_or_missing(raw_id : Int) -> Int {
  @runtime.connection_id_to_index_or_missing(raw_id)
}

///|
fn hiragana_length_penalty(token_len : Int, run_len : Int) -> Int {
  let run_len = if run_len > 0 { run_len } else { token_len }
  if token_len <= 1 {
    if run_len >= 2 {
      -200
    } else {
      0
    }
  } else {
    // Keep function words short in unknown-mode decoding.
    let base = (token_len - 1) * 900
    let tail = run_len - token_len
    // Avoid unstable 2+1 style splits in short hiragana runs.
    if tail == 1 {
      base + 1400
    } else {
      base
    }
  }
}

///|
fn kanji_length_penalty(token_len : Int) -> Int {
  if token_len <= 1 {
    150
  } else if token_len == 2 {
    -250
  } else {
    // Mildly discourage over-long unknown kanji compounds.
    (token_len - 2) * 120
  }
}

///|
fn katakana_span_penalty(token_len : Int, run_len : Int) -> Int {
  let run_len = if run_len > 0 { run_len } else { token_len }
  let split_penalty = if token_len < run_len {
    (run_len - token_len) * 220
  } else {
    0
  }
  let long_bonus = if token_len >= 3 { -120 } else { 0 }
  split_penalty + long_bonus
}

///|
fn ascii_span_penalty(pos : @types.POS, token_len : Int, run_len : Int) -> Int {
  let run_len = if run_len > 0 { run_len } else { token_len }
  if pos == @types.POS::Unknown {
    1200
  } else if token_len == run_len {
    -300
  } else {
    (run_len - token_len) * 250
  }
}

///|
pub fn emission_adjustment(
  pos : @types.POS,
  cls : @types.CharClass,
  token_len : Int,
  run_len : Int,
) -> Int {
  let token_len = if token_len > 0 { token_len } else { 1 }
  match cls {
    @types.CharClass::Hiragana => hiragana_length_penalty(token_len, run_len)
    @types.CharClass::Kanji => kanji_length_penalty(token_len)
    @types.CharClass::Katakana => katakana_span_penalty(token_len, run_len)
    @types.CharClass::AsciiAlpha => ascii_span_penalty(pos, token_len, run_len)
    @types.CharClass::AsciiDigit => ascii_span_penalty(pos, token_len, run_len)
    _ => 0
  }
}
