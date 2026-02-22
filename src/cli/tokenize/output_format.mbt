///|
pub fn format_wakati(tokens : Array[@types.Morpheme]) -> String {
  if tokens.is_empty() {
    return ""
  }
  let surfaces = tokens.map(fn(token) { token.surface }).join(" ")
  "\{surfaces} "
}

///|
pub fn format_mecab(tokens : Array[@types.Morpheme]) -> String {
  let b = StringBuilder::new(size_hint=tokens.length() * 40)
  for token in tokens {
    b.write_string(token.surface)
    b.write_char('\t')
    b.write_string(token.mecab_feature)
    b.write_char('\n')
  }
  b.write_string("EOS")
  b.to_string()
}

///|
pub fn format_tokens(tokens : Array[@types.Morpheme], mode : Int) -> String {
  match mode {
    OUTPUT_MECAB => format_mecab(tokens)
    OUTPUT_WAKATI => format_wakati(tokens)
    OUTPUT_NONE => ""
    OUTPUT_COUNT => ""
    _ => format_mecab(tokens)
  }
}

///|
pub fn format_nbest(
  results : Array[@types.NBestResult],
  mode : Int,
) -> String {
  if results.is_empty() {
    return match mode {
      OUTPUT_MECAB => "EOS"
      OUTPUT_WAKATI => ""
      _ => ""
    }
  }
  let b = StringBuilder::new(size_hint=results.length() * 100)
  for i, result in results {
    if i > 0 && mode == OUTPUT_MECAB {
      b.write_char('\n')
    }
    let formatted = format_tokens(result.morphemes, mode)
    b.write_string(formatted)
    if mode == OUTPUT_WAKATI && i < results.length() - 1 {
      b.write_char('\n')
    }
  }
  b.to_string()
}
