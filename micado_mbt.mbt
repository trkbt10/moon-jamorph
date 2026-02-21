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
pub fn tokenize_utf8(input : BytesView) -> Array[@types.Morpheme] {
  @tok.tokenize_utf8(input)
}

///|
pub fn token_count(input : String) -> Int {
  @tok.token_count(input)
}
