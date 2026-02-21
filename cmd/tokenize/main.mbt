///|
extern "c" fn c_getchar_unlocked() -> Int = "getchar_unlocked"

///|
fn usage() -> Unit {
  println("micado tokenize (mecab-compatible subset)")
  println("Usage: cmd/tokenize [options]")
  println("")
  println("options:")
  println("  -h, --help                   show this help and exit")
  println(
    "  -d, --dicdir=DIR             accepted for compatibility (currently ignored)",
  )
  println(
    "  -O, --output-format-type=TYPE  mecab(default) | wakati | none | count(custom)",
  )
  println("  -N, --nbest=INT              output N best results (default 1)")
  println(
    "  -e, --edition <name>         nano | mini | standard | full (micado extension)",
  )
  println("      --no-unknown             disallow unknown-token paths")
  println(
    "      --must-break <csv>       require token boundary at positions (micado extension)",
  )
  println(
    "      --forbid-break <csv>     forbid token boundary at positions (micado extension)",
  )
  println(
    "      --must-cover-span <csv>  require exact token spans (micado extension)",
  )
  println(
    "      --allow-pos <csv>        allow only POS in csv (micado extension)",
  )
  println(
    "      --disallow-pos <csv>     disallow POS in csv (micado extension)",
  )
  println("")
  println("examples:")
  println(
    "  printf '太郎は走る\\n' | moon run --target native cmd/tokenize --",
  )
  println(
    "  printf '太郎は走る\\n' | moon run --target native cmd/tokenize -- -O wakati",
  )
  println(
    "  printf '龘龘龘\\n' | moon run --target native cmd/tokenize -- -N2 -O wakati --must-break 1",
  )
}

///|
fn decode_line_buffer(line_buf : @buffer.Buffer) -> String {
  let raw = @utf8.decode_lossy(line_buf.to_bytes()[:])
  if raw.length() > 0 && raw.unsafe_get(raw.length() - 1) == '\r' {
    raw.unsafe_substring(start=0, end=raw.length() - 1)
  } else {
    raw
  }
}

///|
fn print_wakati(tokens : Array[@types.Morpheme]) -> Unit {
  if tokens.is_empty() {
    println("")
    return
  }
  let surfaces = tokens.map(token => token.surface).join(" ")
  println("\{surfaces} ")
}

///|
fn print_mecab(tokens : Array[@types.Morpheme]) -> Unit {
  for token in tokens {
    println("\{token.surface}\t\{token.mecab_feature}")
  }
  println("EOS")
}

///|
fn process_line(
  tokenizer : @tok.Tokenizer,
  options : CLIOptions,
  line : String,
) -> Int {
  let parse_options = build_parse_options(options)
  if options.nbest <= 1 {
    let tokens = tokenizer.tokenize_with_options(line, parse_options)
    if options.output_mode == OUTPUT_MECAB {
      print_mecab(tokens)
    } else if options.output_mode == OUTPUT_WAKATI {
      print_wakati(tokens)
    }
    return tokens.length()
  }
  let nbest = tokenizer.tokenize_nbest_with_options(
    line,
    options.nbest,
    parse_options,
  )
  if nbest.is_empty() {
    if options.output_mode == OUTPUT_MECAB {
      println("EOS")
    } else if options.output_mode == OUTPUT_WAKATI {
      println("")
    }
    return 0
  }
  let mut first_len = 0
  for i in 0..<nbest.length() {
    let tokens = nbest[i].morphemes
    if i == 0 {
      first_len = tokens.length()
    }
    if options.output_mode == OUTPUT_MECAB {
      print_mecab(tokens)
    } else if options.output_mode == OUTPUT_WAKATI {
      print_wakati(tokens)
    }
  }
  first_len
}

///|
fn main {
  let args = @env.args()
  let (options, error, show_help) = parse_cli_args(args)
  if show_help {
    usage()
    return
  }
  if error is Some(msg) {
    println("error: \{msg}")
    usage()
    return
  }
  let tokenizer = @tok.Tokenizer::new().set_edition(options.edition)
  if options.dicdir is Some(_) {
    // Parsed for MeCab CLI compatibility. Current tokenizer does not use external dicdir.
  }
  let line_buf = @buffer.new(size_hint=256)
  let mut sentence_total = 0
  let mut token_total = 0
  while true {
    let ch = c_getchar_unlocked()
    if ch < 0 {
      break
    }
    if ch == 0x0A {
      let line = decode_line_buffer(line_buf)
      line_buf.reset()
      sentence_total = sentence_total + 1
      token_total = token_total + process_line(tokenizer, options, line)
    } else {
      line_buf.write_byte(ch.to_byte())
    }
  }
  let tail = decode_line_buffer(line_buf)
  if tail.length() > 0 {
    sentence_total = sentence_total + 1
    token_total = token_total + process_line(tokenizer, options, tail)
  }
  if options.output_mode == OUTPUT_COUNT {
    println("sentences=\{sentence_total} tokens=\{token_total}")
  }
}
