///|
pub type Edition = Int

///|
pub type Mode = Int

///|
type Morpheme = @types.Morpheme

///|
pub const EDITION_NANO = 0

///|
pub const EDITION_MINI = 1

///|
pub const EDITION_STANDARD = 2

///|
pub const EDITION_FULL = 3

///|
pub const MODE_NORMAL = 0

///|
pub const MODE_SEARCH = 1

///|
pub struct Tokenizer {
  edition : Edition
  mode : Mode
  use_lexmatch_scanner : Bool
}

///|
pub fn Tokenizer::new() -> Tokenizer {
  { edition: EDITION_NANO, mode: MODE_NORMAL, use_lexmatch_scanner: false }
}

///|
pub fn Tokenizer::set_edition(self : Tokenizer, edition : Edition) -> Tokenizer {
  { ..self, edition, }
}

///|
pub fn Tokenizer::set_mode(self : Tokenizer, mode : Mode) -> Tokenizer {
  { ..self, mode, }
}

///|
pub fn Tokenizer::set_use_lexmatch_scanner(
  self : Tokenizer,
  enabled : Bool,
) -> Tokenizer {
  { ..self, use_lexmatch_scanner: enabled }
}

///|
pub fn Tokenizer::tokenize(self : Tokenizer, input : String) -> Array[Morpheme] {
  if input.length() == 0 {
    return []
  }
  let chars = input.to_array()
  let (classes, run_lengths) = if self.use_lexmatch_scanner {
    @scanner.scan_char_classes_lexmatch_chars_with_run_lengths(chars)
  } else {
    @scanner.scan_char_classes_manual_chars_with_run_lengths(chars)
  }
  @viterbi.decode_viterbi_with_precomputed(input, chars, classes, run_lengths)
}

///|
pub fn Tokenizer::tokenize_utf8(
  self : Tokenizer,
  input : BytesView,
) -> Array[Morpheme] {
  if input.length() == 0 {
    return []
  }
  let text = @utf8.decode_lossy(input)
  let chars = text.to_array()
  let (classes, run_lengths) = if self.use_lexmatch_scanner {
    @scanner.scan_char_classes_lexmatch_chars_with_run_lengths(chars)
  } else {
    @scanner8.scan_char_classes_manual_utf8_with_run_lengths(input)
  }
  @viterbi.decode_viterbi_with_precomputed(text, chars, classes, run_lengths)
}

///|
pub fn tokenize(input : String) -> Array[Morpheme] {
  Tokenizer::new().tokenize(input)
}

///|
pub fn tokenize_utf8(input : BytesView) -> Array[Morpheme] {
  Tokenizer::new().tokenize_utf8(input)
}
