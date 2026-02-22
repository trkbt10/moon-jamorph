///|
let args_buffer : Ref[@buffer.Buffer] = @ref.new(@buffer.new(size_hint=256))

///|
let args_list : Ref[Array[String]] = @ref.new([])

///|
let line_buffer : Ref[@buffer.Buffer] = @ref.new(@buffer.new(size_hint=1024))

///|
let dic_input_buffer : Ref[@buffer.Buffer] = @ref.new(
  @buffer.new(size_hint=1 << 20),
)

///|
let output_bytes : Ref[Bytes] = @ref.new(Bytes::new(0))

///|
let cli_options : Ref[@cli_tokenize.CLIOptions] = @ref.new(
  @cli_tokenize.CLIOptions::default(),
)

///|
let tokenizer : Ref[@tokenizer.Tokenizer?] = @ref.new(None)

///|
let sentence_count : Ref[Int] = @ref.new(0)

///|
let token_count : Ref[Int] = @ref.new(0)

///|
let cli_error : Ref[String?] = @ref.new(None)

///|
let show_help : Ref[Bool] = @ref.new(false)

// ============================================================================
// CLI Arguments API
// ============================================================================

///|
pub fn reset_args() -> Unit {
  args_buffer.val.reset()
  args_list.val = []
}

///|
pub fn push_arg_byte(byte_value : Int) -> Unit {
  let clamped = if byte_value < 0 {
    0
  } else if byte_value > 255 {
    255
  } else {
    byte_value
  }
  args_buffer.val.write_byte(clamped.to_byte())
}

///|
pub fn finalize_arg() -> Unit {
  let arg = @utf8.decode_lossy(args_buffer.val.to_bytes()[:])
  args_list.val.push(arg)
  args_buffer.val.reset()
}

///|
pub fn init_cli() -> Int {
  let (options, error, help) = @cli_tokenize.parse_cli_args(args_list.val)
  cli_options.val = options
  cli_error.val = error
  show_help.val = help
  sentence_count.val = 0
  token_count.val = 0
  if help {
    let help_text = get_help_text()
    output_bytes.val = @utf8.encode(help_text[:])
    return -2
  }
  if options.show_version {
    output_bytes.val = @utf8.encode(get_version_text()[:])
    return -3
  }
  if error is Some(msg) {
    output_bytes.val = @utf8.encode("error: \{msg}\n"[:])
    return -1
  }
  tokenizer.val = Some(@tokenizer.Tokenizer::new().set_edition(options.edition))
  0
}

///|
fn get_version_text() -> String {
  "micado 0.1.4"
}

///|
pub fn get_input_text_count() -> Int {
  cli_options.val.input_texts.length()
}

///|
pub fn process_input_text(index : Int) -> Int {
  let texts = cli_options.val.input_texts
  if index < 0 || index >= texts.length() {
    return -1
  }
  let tok = match tokenizer.val {
    Some(t) => t
    None => {
      output_bytes.val = @utf8.encode("error: CLI not initialized\n"[:])
      return -1
    }
  }
  let options = cli_options.val
  let text = texts[index]
  let parse_options = @cli_tokenize.build_parse_options(options)
  sentence_count.val = sentence_count.val + 1
  let output : String = if options.nbest <= 1 {
    let tokens = tok.tokenize_with_options(text, parse_options)
    token_count.val = token_count.val + tokens.length()
    @cli_tokenize.format_tokens(tokens, options.output_mode)
  } else {
    let nbest = tok.tokenize_nbest_with_options(text, options.nbest, parse_options)
    if nbest.length() > 0 {
      token_count.val = token_count.val + nbest[0].morphemes.length()
    }
    @cli_tokenize.format_nbest(nbest, options.output_mode)
  }
  output_bytes.val = @utf8.encode(output[:])
  output_bytes.val.length()
}

///|
fn get_help_text() -> String {
  let lines = [
    "micado: MeCab-compatible Japanese morphological analyzer",
    "",
    "Usage: micado [options] [text...]",
    "",
    "MeCab-compatible options:",
    "  -d, --dicdir=DIR               dictionary directory (native only; WASM: use buffer API)",
    "  -O, --output-format-type=TYPE  output format: mecab(default) | wakati | none",
    "  -N, --nbest=INT                output N best results (default 1)",
    "  -p, --partial                  partial parsing mode",
    "  -v, --version                  show version and exit",
    "  -h, --help                     show this help and exit",
    "",
    "micado extensions:",
    "  -e, --edition <name>           dictionary: tiny | mini | medium | full",
    "  -O count                       output sentence/token counts",
    "      --no-unknown               disallow unknown-token paths",
    "      --must-break <csv>         require boundary at positions",
    "      --forbid-break <csv>       forbid boundary at positions",
    "      --must-cover-span <csv>    require exact spans (start:end)",
    "      --allow-pos <csv>          allow only specified POS",
    "      --disallow-pos <csv>       disallow specified POS",
    "",
    "Examples:",
    "  micado \"吾輩は猫である\"",
    "  echo \"太郎は走る\" | micado",
    "  micado -O wakati \"すもももももも\"",
    "  micado -N 3 \"すもももももも\"",
  ]
  lines.join("\n")
}

// ============================================================================
// Line Processing API
// ============================================================================

///|
pub fn reset_line() -> Unit {
  line_buffer.val.reset()
}

///|
pub fn push_line_byte(byte_value : Int) -> Unit {
  let clamped = if byte_value < 0 {
    0
  } else if byte_value > 255 {
    255
  } else {
    byte_value
  }
  line_buffer.val.write_byte(clamped.to_byte())
}

///|
fn decode_line_buffer() -> String {
  let raw = @utf8.decode_lossy(line_buffer.val.to_bytes()[:])
  if raw.length() > 0 && raw.unsafe_get(raw.length() - 1) == '\r' {
    raw.unsafe_substring(start=0, end=raw.length() - 1)
  } else {
    raw
  }
}

///|
pub fn process_line() -> Int {
  let tok = match tokenizer.val {
    Some(t) => t
    None => {
      output_bytes.val = @utf8.encode("error: CLI not initialized\n"[:])
      return -1
    }
  }
  let options = cli_options.val
  let line = decode_line_buffer()
  let parse_options = @cli_tokenize.build_parse_options(options)
  sentence_count.val = sentence_count.val + 1
  let output : String = if options.nbest <= 1 {
    let tokens = tok.tokenize_with_options(line, parse_options)
    token_count.val = token_count.val + tokens.length()
    @cli_tokenize.format_tokens(tokens, options.output_mode)
  } else {
    let nbest = tok.tokenize_nbest_with_options(line, options.nbest, parse_options)
    if nbest.length() > 0 {
      token_count.val = token_count.val + nbest[0].morphemes.length()
    }
    @cli_tokenize.format_nbest(nbest, options.output_mode)
  }
  output_bytes.val = @utf8.encode(output[:])
  output_bytes.val.length()
}

///|
pub fn get_sentence_count() -> Int {
  sentence_count.val
}

///|
pub fn get_token_count() -> Int {
  token_count.val
}

// ============================================================================
// Output API
// ============================================================================

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

// ============================================================================
// Dictionary Loading API
// ============================================================================

///|
pub fn reset_dic_input() -> Unit {
  dic_input_buffer.val.reset()
}

///|
pub fn push_dic_input_byte(byte_value : Int) -> Unit {
  let clamped = if byte_value < 0 {
    0
  } else if byte_value > 255 {
    255
  } else {
    byte_value
  }
  dic_input_buffer.val.write_byte(clamped.to_byte())
}

///|
pub fn load_dic_bin() -> Int {
  let dic_bytes = dic_input_buffer.val.to_bytes()
  let ok = @runtime.load_dic_bin(dic_bytes[:])
  if ok {
    @runtime.entry_count()
  } else {
    -1
  }
}

///|
fn main {
  ()
}
