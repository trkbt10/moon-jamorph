///|
extern "c" fn c_getchar_unlocked() -> Int = "getchar_unlocked"

///|
type OutputMode = Int

///|
const OUTPUT_MECAB = 0

///|
const OUTPUT_WAKATI = 1

///|
const OUTPUT_NONE = 2

///|
const OUTPUT_COUNT = 3

///|
struct CLIOptions {
  edition : Int
  output_mode : OutputMode
  dicdir : String?
  nbest : Int
  allow_unknown : Bool
  must_break_positions : Array[Int]
  forbid_break_positions : Array[Int]
  allowed_pos : Array[@types.POS]
  disallowed_pos : Array[@types.POS]
  must_cover_spans : Array[@types.SpanConstraint]
}

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
fn parse_edition_name(name : String) -> Int {
  match name.to_lower() {
    "nano" => @tok.EDITION_NANO
    "mini" => @tok.EDITION_MINI
    "standard" => @tok.EDITION_STANDARD
    "full" => @tok.EDITION_FULL
    _ => -1
  }
}

///|
fn parse_output_mode(name : String) -> OutputMode {
  match normalize_cli_token(name) {
    "mecab" => OUTPUT_MECAB
    "default" => OUTPUT_MECAB
    "wakati" => OUTPUT_WAKATI
    "none" => OUTPUT_NONE
    "count" => OUTPUT_COUNT
    _ => -1
  }
}

///|
fn normalize_cli_token(text : String) -> String {
  let b = StringBuilder::new(size_hint=text.length())
  for ch in text {
    if ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n' {
      b.write_char(ch)
    }
  }
  b.to_string().to_lower()
}

///|
fn parse_non_negative_int(text : String) -> Int {
  let normalized = normalize_cli_token(text)
  if normalized.length() == 0 {
    return -1
  }
  let mut value = 0
  for ch in normalized {
    let cp = ch.to_int()
    if cp < '0'.to_int() || cp > '9'.to_int() {
      return -1
    }
    value = value * 10 + (cp - '0'.to_int())
  }
  value
}

///|
fn parse_int_list(csv : String) -> Array[Int]? {
  if csv.length() == 0 {
    return Some([])
  }
  let results : Array[Int] = []
  let parts = csv.split(",").map(StringView::to_string).collect()
  for part in parts {
    let value = parse_non_negative_int(normalize_cli_token(part))
    if value < 0 {
      return None
    }
    results.push(value)
  }
  Some(results)
}

///|
fn parse_pos_name(name : String) -> @types.POS? {
  let n = normalize_cli_token(name)
  if n == "bos-eos" || n == "bos/eos" || n == "bos_eos" || n == "boseos" {
    return Some(@types.POS::BosEos)
  }
  if n == "noun-general" ||
    n == "noun_general" ||
    n == "noungeneral" ||
    n == "noun" {
    return Some(@types.POS::NounGeneral)
  }
  if n == "noun-proper" || n == "noun_proper" || n == "nounproper" {
    return Some(@types.POS::NounProper)
  }
  if n == "noun-non-independent" ||
    n == "noun_non_independent" ||
    n == "nounnonindependent" ||
    n == "noun-nonindependent" {
    return Some(@types.POS::NounNonIndependent)
  }
  if n == "particle" {
    return Some(@types.POS::Particle)
  }
  if n == "unknown" {
    return Some(@types.POS::Unknown)
  }
  None
}

///|
fn parse_pos_list(csv : String) -> Array[@types.POS]? {
  if csv.length() == 0 {
    return Some([])
  }
  let results : Array[@types.POS] = []
  let parts = csv.split(",").map(StringView::to_string).collect()
  for part in parts {
    match parse_pos_name(part) {
      Some(pos) => results.push(pos)
      None => return None
    }
  }
  Some(results)
}

///|
fn parse_span_list(csv : String) -> Array[@types.SpanConstraint]? {
  if csv.length() == 0 {
    return Some([])
  }
  let results : Array[@types.SpanConstraint] = []
  let spans = csv.split(",").map(StringView::to_string).collect()
  for span_text in spans {
    let parts = normalize_cli_token(span_text)
      .split(":")
      .map(StringView::to_string)
      .collect()
    if parts.length() != 2 {
      return None
    }
    let start_pos = parse_non_negative_int(parts[0])
    let end_pos = parse_non_negative_int(parts[1])
    if start_pos < 0 || end_pos < 0 || start_pos >= end_pos {
      return None
    }
    results.push({ start_pos, end_pos })
  }
  Some(results)
}

///|
fn build_options(
  edition : Int,
  output_mode : OutputMode,
  dicdir : String?,
  nbest : Int,
  allow_unknown : Bool,
  must_break_positions : Array[Int],
  forbid_break_positions : Array[Int],
  allowed_pos : Array[@types.POS],
  disallowed_pos : Array[@types.POS],
  must_cover_spans : Array[@types.SpanConstraint],
) -> CLIOptions {
  {
    edition,
    output_mode,
    dicdir,
    nbest,
    allow_unknown,
    must_break_positions,
    forbid_break_positions,
    allowed_pos,
    disallowed_pos,
    must_cover_spans,
  }
}

///|
fn build_parse_options(options : CLIOptions) -> @types.ParseOptions {
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

///|
fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
  let mut edition = @tok.EDITION_FULL
  let mut output_mode = OUTPUT_MECAB
  let mut dicdir : String? = None
  let mut nbest = 1
  let mut allow_unknown = true
  let mut must_break_positions : Array[Int] = []
  let mut forbid_break_positions : Array[Int] = []
  let mut allowed_pos : Array[@types.POS] = []
  let mut disallowed_pos : Array[@types.POS] = []
  let mut must_cover_spans : Array[@types.SpanConstraint] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      return (
        build_options(
          edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
          forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
        ),
        None,
        true,
      )
    }
    if arg == "-e" || arg == "--edition" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --edition"),
          false,
        )
      }
      let parsed = parse_edition_name(args[i + 1])
      if parsed < 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some(
            "unknown edition: \{args[i + 1]} (expected nano|mini|standard|full)",
          ),
          false,
        )
      }
      edition = parsed
      i = i + 2
      continue
    }
    if arg == "-O" || arg == "--output" || arg == "--output-format-type" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --output-format-type"),
          false,
        )
      }
      let parsed = parse_output_mode(args[i + 1])
      if parsed < 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some(
            "unknown output mode: \{args[i + 1]} (expected mecab|wakati|none|count)",
          ),
          false,
        )
      }
      output_mode = parsed
      i = i + 2
      continue
    }
    if arg.has_prefix("-O") && arg.length() > 2 {
      let value = arg.unsafe_substring(start=2, end=arg.length())
      let parsed = parse_output_mode(value)
      if parsed < 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some(
            "unknown output mode: \{value} (expected mecab|wakati|none|count)",
          ),
          false,
        )
      }
      output_mode = parsed
      i = i + 1
      continue
    }
    if arg.has_prefix("--output-format-type=") {
      let value = arg.unsafe_substring(start=21, end=arg.length())
      let parsed = parse_output_mode(value)
      if parsed < 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some(
            "unknown output mode: \{value} (expected mecab|wakati|none|count)",
          ),
          false,
        )
      }
      output_mode = parsed
      i = i + 1
      continue
    }
    if arg == "-d" || arg == "--dicdir" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --dicdir"),
          false,
        )
      }
      dicdir = Some(args[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("--dicdir=") {
      let value = arg.unsafe_substring(start=9, end=arg.length())
      dicdir = Some(value)
      i = i + 1
      continue
    }
    if arg == "-N" || arg == "--nbest" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --nbest"),
          false,
        )
      }
      let parsed = parse_non_negative_int(args[i + 1])
      if parsed <= 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some(
            "invalid --nbest value: \{args[i + 1]} (expected positive integer)",
          ),
          false,
        )
      }
      nbest = parsed
      i = i + 2
      continue
    }
    if arg.has_prefix("-N") && arg.length() > 2 {
      let value = arg.unsafe_substring(start=2, end=arg.length())
      let parsed = parse_non_negative_int(value)
      if parsed <= 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("invalid --nbest value: \{value} (expected positive integer)"),
          false,
        )
      }
      nbest = parsed
      i = i + 1
      continue
    }
    if arg.has_prefix("--nbest=") {
      let value = arg.unsafe_substring(start=8, end=arg.length())
      let parsed = parse_non_negative_int(value)
      if parsed <= 0 {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("invalid --nbest value: \{value} (expected positive integer)"),
          false,
        )
      }
      nbest = parsed
      i = i + 1
      continue
    }
    if arg == "--no-unknown" {
      allow_unknown = false
      i = i + 1
      continue
    }
    if arg == "--must-break" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --must-break"),
          false,
        )
      }
      match parse_int_list(args[i + 1]) {
        Some(parsed) => must_break_positions = parsed
        None =>
          return (
            build_options(
              edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
              forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
            ),
            Some(
              "invalid --must-break value: \{args[i + 1]} (expected csv of non-negative integers)",
            ),
            false,
          )
      }
      i = i + 2
      continue
    }
    if arg == "--forbid-break" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --forbid-break"),
          false,
        )
      }
      match parse_int_list(args[i + 1]) {
        Some(parsed) => forbid_break_positions = parsed
        None =>
          return (
            build_options(
              edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
              forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
            ),
            Some(
              "invalid --forbid-break value: \{args[i + 1]} (expected csv of non-negative integers)",
            ),
            false,
          )
      }
      i = i + 2
      continue
    }
    if arg == "--must-cover-span" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --must-cover-span"),
          false,
        )
      }
      match parse_span_list(args[i + 1]) {
        Some(parsed) => must_cover_spans = parsed
        None =>
          return (
            build_options(
              edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
              forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
            ),
            Some(
              "invalid --must-cover-span value: \{args[i + 1]} (expected csv of start:end with start < end)",
            ),
            false,
          )
      }
      i = i + 2
      continue
    }
    if arg == "--allow-pos" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --allow-pos"),
          false,
        )
      }
      match parse_pos_list(args[i + 1]) {
        Some(parsed) => allowed_pos = parsed
        None =>
          return (
            build_options(
              edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
              forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
            ),
            Some(
              "invalid --allow-pos value: \{args[i + 1]} (expected csv of pos names)",
            ),
            false,
          )
      }
      i = i + 2
      continue
    }
    if arg == "--disallow-pos" {
      if i + 1 >= args.length() {
        return (
          build_options(
            edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
            forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
          ),
          Some("missing value for --disallow-pos"),
          false,
        )
      }
      match parse_pos_list(args[i + 1]) {
        Some(parsed) => disallowed_pos = parsed
        None =>
          return (
            build_options(
              edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
              forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
            ),
            Some(
              "invalid --disallow-pos value: \{args[i + 1]} (expected csv of pos names)",
            ),
            false,
          )
      }
      i = i + 2
      continue
    }
    return (
      build_options(
        edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions,
        forbid_break_positions, allowed_pos, disallowed_pos, must_cover_spans,
      ),
      Some("unknown option: \{arg}"),
      false,
    )
  }
  (
    build_options(
      edition, output_mode, dicdir, nbest, allow_unknown, must_break_positions, forbid_break_positions,
      allowed_pos, disallowed_pos, must_cover_spans,
    ),
    None,
    false,
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
