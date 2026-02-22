///|
fn parse_edition_name(name : String) -> Int {
  match name.to_lower() {
    "nano" | "tiny" => @tokenizer.EDITION_NANO
    "mini" => @tokenizer.EDITION_MINI
    "standard" | "medium" => @tokenizer.EDITION_STANDARD
    "full" => @tokenizer.EDITION_FULL
    _ => -1
  }
}

///|
fn parse_output_mode(name : String) -> Int {
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
  if n == "noun-general" || n == "noun_general" || n == "noungeneral" || n == "noun" {
    return Some(@types.POS::NounGeneral)
  }
  if n == "noun-proper" || n == "noun_proper" || n == "nounproper" {
    return Some(@types.POS::NounProper)
  }
  if n == "noun-non-independent" || n == "noun_non_independent" || n == "nounnonindependent" || n == "noun-nonindependent" {
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
struct ParseState {
  mut edition : Int
  mut output_mode : Int
  mut dicdir : String?
  mut nbest : Int
  mut allow_unknown : Bool
  mut partial_mode : Bool
  mut must_break_positions : Array[Int]
  mut forbid_break_positions : Array[Int]
  mut allowed_pos : Array[@types.POS]
  mut disallowed_pos : Array[@types.POS]
  mut must_cover_spans : Array[@types.SpanConstraint]
  input_texts : Array[String]
  mut show_version : Bool
}

///|
fn ParseState::new() -> ParseState {
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
fn ParseState::to_options(self : ParseState) -> CLIOptions {
  {
    edition: self.edition,
    output_mode: self.output_mode,
    dicdir: self.dicdir,
    nbest: self.nbest,
    allow_unknown: self.allow_unknown,
    partial_mode: self.partial_mode,
    must_break_positions: self.must_break_positions,
    forbid_break_positions: self.forbid_break_positions,
    allowed_pos: self.allowed_pos,
    disallowed_pos: self.disallowed_pos,
    must_cover_spans: self.must_cover_spans,
    input_texts: self.input_texts,
    show_version: self.show_version,
  }
}

///|
fn try_parse_option_with_value(
  arg : String,
  prefix : String,
) -> String? {
  if arg.has_prefix(prefix) && arg.length() > prefix.length() {
    Some(arg.unsafe_substring(start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
pub fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
  let state = ParseState::new()
  let mut i = 0
  while i < args.length() {
    let arg = args[i]

    // Help
    if arg == "-h" || arg == "--help" {
      return (state.to_options(), None, true)
    }

    // Version (MeCab compatible)
    if arg == "-v" || arg == "--version" {
      state.show_version = true
      return (state.to_options(), None, false)
    }

    // Partial mode (MeCab compatible)
    if arg == "-p" || arg == "--partial" {
      state.partial_mode = true
      i = i + 1
      continue
    }

    // Edition (micado extension)
    if arg == "-e" || arg == "--edition" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --edition"), false)
      }
      let parsed = parse_edition_name(args[i + 1])
      if parsed < 0 {
        return (state.to_options(), Some("unknown edition: \{args[i + 1]} (expected nano|mini|standard|full)"), false)
      }
      state.edition = parsed
      i = i + 2
      continue
    }

    // Output format type (MeCab compatible)
    if arg == "-O" || arg == "--output" || arg == "--output-format-type" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --output-format-type"), false)
      }
      let parsed = parse_output_mode(args[i + 1])
      if parsed < 0 {
        return (state.to_options(), Some("unknown output mode: \{args[i + 1]} (expected mecab|wakati|none|count)"), false)
      }
      state.output_mode = parsed
      i = i + 2
      continue
    }
    if try_parse_option_with_value(arg, "-O") is Some(value) {
      let parsed = parse_output_mode(value)
      if parsed < 0 {
        return (state.to_options(), Some("unknown output mode: \{value} (expected mecab|wakati|none|count)"), false)
      }
      state.output_mode = parsed
      i = i + 1
      continue
    }
    if try_parse_option_with_value(arg, "--output-format-type=") is Some(value) {
      let parsed = parse_output_mode(value)
      if parsed < 0 {
        return (state.to_options(), Some("unknown output mode: \{value} (expected mecab|wakati|none|count)"), false)
      }
      state.output_mode = parsed
      i = i + 1
      continue
    }

    // Dictionary directory (MeCab compatible, accepted but ignored)
    if arg == "-d" || arg == "--dicdir" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --dicdir"), false)
      }
      state.dicdir = Some(args[i + 1])
      i = i + 2
      continue
    }
    if try_parse_option_with_value(arg, "--dicdir=") is Some(value) {
      state.dicdir = Some(value)
      i = i + 1
      continue
    }

    // N-best (MeCab compatible)
    if arg == "-N" || arg == "--nbest" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --nbest"), false)
      }
      let parsed = parse_non_negative_int(args[i + 1])
      if parsed <= 0 {
        return (state.to_options(), Some("invalid --nbest value: \{args[i + 1]} (expected positive integer)"), false)
      }
      state.nbest = parsed
      i = i + 2
      continue
    }
    if try_parse_option_with_value(arg, "-N") is Some(value) {
      let parsed = parse_non_negative_int(value)
      if parsed <= 0 {
        return (state.to_options(), Some("invalid --nbest value: \{value} (expected positive integer)"), false)
      }
      state.nbest = parsed
      i = i + 1
      continue
    }
    if try_parse_option_with_value(arg, "--nbest=") is Some(value) {
      let parsed = parse_non_negative_int(value)
      if parsed <= 0 {
        return (state.to_options(), Some("invalid --nbest value: \{value} (expected positive integer)"), false)
      }
      state.nbest = parsed
      i = i + 1
      continue
    }

    // No unknown (micado extension)
    if arg == "--no-unknown" {
      state.allow_unknown = false
      i = i + 1
      continue
    }

    // Must break (micado extension)
    if arg == "--must-break" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --must-break"), false)
      }
      match parse_int_list(args[i + 1]) {
        Some(parsed) => state.must_break_positions = parsed
        None => return (state.to_options(), Some("invalid --must-break value: \{args[i + 1]} (expected csv of non-negative integers)"), false)
      }
      i = i + 2
      continue
    }

    // Forbid break (micado extension)
    if arg == "--forbid-break" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --forbid-break"), false)
      }
      match parse_int_list(args[i + 1]) {
        Some(parsed) => state.forbid_break_positions = parsed
        None => return (state.to_options(), Some("invalid --forbid-break value: \{args[i + 1]} (expected csv of non-negative integers)"), false)
      }
      i = i + 2
      continue
    }

    // Must cover span (micado extension)
    if arg == "--must-cover-span" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --must-cover-span"), false)
      }
      match parse_span_list(args[i + 1]) {
        Some(parsed) => state.must_cover_spans = parsed
        None => return (state.to_options(), Some("invalid --must-cover-span value: \{args[i + 1]} (expected csv of start:end)"), false)
      }
      i = i + 2
      continue
    }

    // Allow POS (micado extension)
    if arg == "--allow-pos" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --allow-pos"), false)
      }
      match parse_pos_list(args[i + 1]) {
        Some(parsed) => state.allowed_pos = parsed
        None => return (state.to_options(), Some("invalid --allow-pos value: \{args[i + 1]} (expected csv of pos names)"), false)
      }
      i = i + 2
      continue
    }

    // Disallow POS (micado extension)
    if arg == "--disallow-pos" {
      if i + 1 >= args.length() {
        return (state.to_options(), Some("missing value for --disallow-pos"), false)
      }
      match parse_pos_list(args[i + 1]) {
        Some(parsed) => state.disallowed_pos = parsed
        None => return (state.to_options(), Some("invalid --disallow-pos value: \{args[i + 1]} (expected csv of pos names)"), false)
      }
      i = i + 2
      continue
    }

    // Non-option arguments are input texts (MeCab compatible)
    if not(arg.has_prefix("-")) {
      state.input_texts.push(arg)
      i = i + 1
      continue
    }

    // Unknown option - skip silently for WASM compatibility
    i = i + 1
  }
  (state.to_options(), None, false)
}
