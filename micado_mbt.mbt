///|
pub const EDITION_NANO : Int = @tok.EDITION_NANO

///|
pub const EDITION_MINI : Int = @tok.EDITION_MINI

///|
pub const EDITION_STANDARD : Int = @tok.EDITION_STANDARD

///|
pub const EDITION_FULL : Int = @tok.EDITION_FULL

///|
pub const MODE_NORMAL : Int = @tok.MODE_NORMAL

///|
pub const MODE_SEARCH : Int = @tok.MODE_SEARCH

///|
pub fn new_tokenizer() -> @tok.Tokenizer {
  @tok.Tokenizer::new()
}

///|
pub fn tokenize(input : String) -> Array[@types.Morpheme] {
  @tok.tokenize(input)
}

///|
pub fn tokenize_with_options(
  input : String,
  options : @types.ParseOptions,
) -> Array[@types.Morpheme] {
  @tok.tokenize_with_options(input, options)
}

///|
pub fn tokenize_nbest(input : String, n : Int) -> Array[Array[@types.Morpheme]] {
  @tok.tokenize_nbest(input, n)
}

///|
pub fn tokenize_nbest_with_options(
  input : String,
  n : Int,
  options : @types.ParseOptions,
) -> Array[@types.NBestResult] {
  @tok.tokenize_nbest_with_options(input, n, options)
}

///|
pub fn tokenize_utf8(input : BytesView) -> Array[@types.Morpheme] {
  @tok.tokenize_utf8(input)
}

///|
pub fn tokenize_utf8_with_options(
  input : BytesView,
  options : @types.ParseOptions,
) -> Array[@types.Morpheme] {
  @tok.tokenize_utf8_with_options(input, options)
}

///|
pub fn tokenize_utf8_nbest(
  input : BytesView,
  n : Int,
) -> Array[Array[@types.Morpheme]] {
  @tok.tokenize_utf8_nbest(input, n)
}

///|
pub fn tokenize_utf8_nbest_with_options(
  input : BytesView,
  n : Int,
  options : @types.ParseOptions,
) -> Array[@types.NBestResult] {
  @tok.tokenize_utf8_nbest_with_options(input, n, options)
}

///|
pub fn token_count(input : String) -> Int {
  @tok.token_count(input)
}
