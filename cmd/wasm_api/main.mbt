///|
let input_buffer : Ref[@buffer.Buffer] = @ref.new(@buffer.new(size_hint=256))

///|
let output_bytes : Ref[Bytes] = @ref.new(Bytes::new(0))

///|
fn format_tsv_line(token : @types.Morpheme) -> String {
  "\{token.surface}\t\{token.pos_detail}\t\{token.start_pos}\t\{token.end_pos}"
}

///|
fn tokenize_current_input_to_output(edition : Int) -> Int {
  let input = @utf8.decode_lossy(input_buffer.val.to_bytes()[:])
  let tokenizer = @tok.Tokenizer::new().set_edition(edition)
  let tokens = tokenizer.tokenize(input)
  let b = StringBuilder::new(size_hint=input.length() + tokens.length() * 24)
  for i in 0..<tokens.length() {
    if i > 0 {
      b.write_char('\n')
    }
    b.write_string(format_tsv_line(tokens[i]))
  }
  let text = b.to_string()
  output_bytes.val = @utf8.encode(text[:])
  output_bytes.val.length()
}

///|
pub fn reset_input() -> Unit {
  input_buffer.val.reset()
}

///|
pub fn push_input_byte(byte_value : Int) -> Unit {
  let clamped = if byte_value < 0 {
    0
  } else if byte_value > 255 {
    255
  } else {
    byte_value
  }
  input_buffer.val.write_byte(clamped.to_byte())
}

///|
pub fn tokenize_nano_tsv() -> Int {
  tokenize_current_input_to_output(@tok.EDITION_NANO)
}

///|
pub fn tokenize_mini_tsv() -> Int {
  tokenize_current_input_to_output(@tok.EDITION_MINI)
}

///|
pub fn output_length() -> Int {
  output_bytes.val.length()
}

///|
pub fn output_byte_at(index : Int) -> Int {
  if index < 0 || index >= output_bytes.val.length() {
    return -1
  }
  output_bytes.val[:][index].to_int()
}

///|
fn main {
  ()
}
