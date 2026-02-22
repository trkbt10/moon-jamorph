///|
pub const OUTPUT_MECAB : Int = 0

///|
pub const OUTPUT_WAKATI : Int = 1

///|
pub const OUTPUT_NONE : Int = 2

///|
pub const OUTPUT_COUNT : Int = 3

///|
pub struct CLIOptions {
  edition : Int
  output_mode : Int
  dicdir : String?
  nbest : Int
  allow_unknown : Bool
  partial_mode : Bool
  must_break_positions : Array[Int]
  forbid_break_positions : Array[Int]
  allowed_pos : Array[@types.POS]
  disallowed_pos : Array[@types.POS]
  must_cover_spans : Array[@types.SpanConstraint]
  input_texts : Array[String]
  show_version : Bool
}

///|
pub fn CLIOptions::default() -> CLIOptions {
  {
    edition: @tokenizer.EDITION_FULL,
    output_mode: OUTPUT_MECAB,
    dicdir: None,
    nbest: 1,
    allow_unknown: true,
    partial_mode: false,
    must_break_positions: [],
    forbid_break_positions: [],
    allowed_pos: [],
    disallowed_pos: [],
    must_cover_spans: [],
    input_texts: [],
    show_version: false,
  }
}

///|
pub fn build_parse_options(options : CLIOptions) -> @types.ParseOptions {
  {
    constraint: {
      allow_unknown: options.allow_unknown,
      must_break_positions: options.must_break_positions,
      forbid_break_positions: options.forbid_break_positions,
      allowed_pos: options.allowed_pos,
      disallowed_pos: options.disallowed_pos,
      must_cover_spans: options.must_cover_spans,
    },
  }
}
