///|
type OutputFormat = Int

///|
const FORMAT_MECAB = 0

///|
const FORMAT_JSON = 1

///|
const FORMAT_WAKATI = 2

///|
struct CLIOptions {
  edition : Int
  format : OutputFormat
  use_lexmatch_scanner : Bool
  text_from_args : String
}

///|
fn usage() -> Unit {
  println("Micado CLI")
  println("usage: moon run cmd/main -- [options] [text]")
  println("")
  println("options:")
  println("  -h, --help                 show this help")
  println("  -d, --edition <name>       nano | mini | standard | full")
  println("  -f, --format <name>        mecab | json | wakati")
  println("  -O <name> / -O<name>       MeCab-style output selector")
  println("  --json                     same as --format json")
  println("  --lexmatch                 use lexmatch scanner")
  println("  --manual                   use manual scanner (default)")
  println("")
  println("input:")
  println("  Pass input text as positional arguments.")
  println("")
  println("examples:")
  println("  moon run cmd/main -- \"すもももももももものうち\"")
  println(
    "  moon run cmd/main -- -d standard -O json \"迅速な形態素解析\"",
  )
  println("  moon run cmd/main -- -d full -O mecab \"#AirPodsを買う\"")
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
fn edition_name(edition : Int) -> String {
  match edition {
    x if x == @tok.EDITION_NANO => "nano"
    x if x == @tok.EDITION_MINI => "mini"
    x if x == @tok.EDITION_STANDARD => "standard"
    x if x == @tok.EDITION_FULL => "full"
    _ => "unknown"
  }
}

///|
fn parse_format_name(name : String) -> OutputFormat {
  match name.to_lower() {
    "mecab" => FORMAT_MECAB
    "json" => FORMAT_JSON
    "wakati" => FORMAT_WAKATI
    _ => -1
  }
}

///|
fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
  let mut edition = @tok.EDITION_NANO
  let mut format = FORMAT_MECAB
  let mut use_lexmatch_scanner = false
  let text_parts : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      let options = {
        edition,
        format,
        use_lexmatch_scanner,
        text_from_args: text_parts.join(" "),
      }
      return (options, None, true)
    }
    if arg == "--json" {
      format = FORMAT_JSON
      i = i + 1
      continue
    }
    if arg == "--lexmatch" {
      use_lexmatch_scanner = true
      i = i + 1
      continue
    }
    if arg == "--manual" {
      use_lexmatch_scanner = false
      i = i + 1
      continue
    }
    if arg == "--" {
      for j in (i + 1)..<args.length() {
        text_parts.push(args[j])
      }
      break
    }
    if arg == "-d" || arg == "--edition" {
      if i + 1 >= args.length() {
        let options = {
          edition,
          format,
          use_lexmatch_scanner,
          text_from_args: text_parts.join(" "),
        }
        return (options, Some("missing value for --edition"), false)
      }
      let parsed = parse_edition_name(args[i + 1])
      if parsed < 0 {
        let options = {
          edition,
          format,
          use_lexmatch_scanner,
          text_from_args: text_parts.join(" "),
        }
        return (
          options,
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
    if arg == "-f" || arg == "--format" || arg == "-O" {
      if i + 1 >= args.length() {
        let options = {
          edition,
          format,
          use_lexmatch_scanner,
          text_from_args: text_parts.join(" "),
        }
        return (options, Some("missing value for --format"), false)
      }
      let parsed = parse_format_name(args[i + 1])
      if parsed < 0 {
        let options = {
          edition,
          format,
          use_lexmatch_scanner,
          text_from_args: text_parts.join(" "),
        }
        return (
          options,
          Some("unknown format: \{args[i + 1]} (expected mecab|json|wakati)"),
          false,
        )
      }
      format = parsed
      i = i + 2
      continue
    }
    if arg.has_prefix("-O") && arg.length() > 2 {
      let value = arg.unsafe_substring(start=2, end=arg.length())
      let parsed = parse_format_name(value)
      if parsed < 0 {
        let options = {
          edition,
          format,
          use_lexmatch_scanner,
          text_from_args: text_parts.join(" "),
        }
        return (
          options,
          Some("unknown format: \{value} (expected mecab|json|wakati)"),
          false,
        )
      }
      format = parsed
      i = i + 1
      continue
    }
    if arg.has_prefix("-") {
      let options = {
        edition,
        format,
        use_lexmatch_scanner,
        text_from_args: text_parts.join(" "),
      }
      return (options, Some("unknown option: \{arg}"), false)
    }
    text_parts.push(arg)
    i = i + 1
  }
  let options = {
    edition,
    format,
    use_lexmatch_scanner,
    text_from_args: text_parts.join(" "),
  }
  (options, None, false)
}

///|
fn json_hex_digit(n : Int) -> Char {
  let x = n & 0xF
  if x < 10 {
    (x + '0'.to_int()).unsafe_to_char()
  } else {
    (x - 10 + 'a'.to_int()).unsafe_to_char()
  }
}

///|
fn append_json_string(dst : StringBuilder, raw : String) -> Unit {
  dst.write_char('"')
  for ch in raw.to_array() {
    let cp = ch.to_int()
    if cp == '"'.to_int() {
      dst.write_string("\\\"")
    } else if cp == '\\'.to_int() {
      dst.write_string("\\\\")
    } else if cp == '\b'.to_int() {
      dst.write_string("\\b")
    } else if cp == '\f'.to_int() {
      dst.write_string("\\f")
    } else if cp == '\n'.to_int() {
      dst.write_string("\\n")
    } else if cp == '\r'.to_int() {
      dst.write_string("\\r")
    } else if cp == '\t'.to_int() {
      dst.write_string("\\t")
    } else if cp >= 0 && cp < 0x20 {
      dst.write_string("\\u00")
      dst.write_char(json_hex_digit(cp >> 4))
      dst.write_char(json_hex_digit(cp))
    } else {
      dst.write_char(ch)
    }
  }
  dst.write_char('"')
}

///|
fn append_json_key(dst : StringBuilder, key : String) -> Unit {
  append_json_string(dst, key)
  dst.write_char(':')
}

///|
fn append_json_string_field(
  dst : StringBuilder,
  key : String,
  value : String,
) -> Unit {
  append_json_key(dst, key)
  append_json_string(dst, value)
}

///|
fn append_json_int_field(
  dst : StringBuilder,
  key : String,
  value : Int,
) -> Unit {
  append_json_key(dst, key)
  dst.write_string(value.to_string())
}

///|
fn render_json(tokens : Array[@types.Morpheme], edition : Int) -> String {
  let b = StringBuilder::new(size_hint=tokens.length() * 80 + 64)
  b.write_char('{')
  append_json_string_field(b, "edition", edition_name(edition))
  b.write_char(',')
  append_json_key(b, "tokens")
  b.write_char('[')
  for i in 0..<tokens.length() {
    let token = tokens[i]
    if i > 0 {
      b.write_char(',')
    }
    b.write_char('{')
    append_json_string_field(b, "surface", token.surface)
    b.write_char(',')
    append_json_string_field(b, "pos", token.pos.label())
    b.write_char(',')
    append_json_string_field(b, "pos_detail", token.pos_detail)
    b.write_char(',')
    append_json_int_field(b, "start_pos", token.start_pos)
    b.write_char(',')
    append_json_int_field(b, "end_pos", token.end_pos)
    b.write_char('}')
  }
  b.write_string("]}")
  b.to_string()
}

///|
fn render_mecab(tokens : Array[@types.Morpheme]) -> String {
  let lines = tokens.map(token => "\{token.surface}\t\{token.pos_detail}")
  lines.push("EOS")
  lines.join("\n")
}

///|
fn render_wakati(tokens : Array[@types.Morpheme]) -> String {
  tokens.map(token => token.surface).join(" ")
}

///|
fn test_morpheme(
  surface : String,
  pos_detail : String,
  start_pos : Int,
  end_pos : Int,
) -> @types.Morpheme {
  { surface, pos: @types.POS::NounGeneral, pos_detail, start_pos, end_pos }
}

///|
test "cli parse should accept mecab compatible options" {
  let (options, error, show_help) = parse_cli_args([
    "cmd/main", "-d", "standard", "-Ojson", "迅速",
  ])
  inspect(show_help, content="false")
  inspect(error, content="None")
  inspect(options.edition, content="2")
  inspect(options.format, content="1")
  inspect(options.text_from_args, content="迅速")
}

///|
test "render_mecab should include EOS line" {
  let out = render_mecab([test_morpheme("迅速", "名詞,一般,*,*", 0, 2)])
  assert_eq(out, "迅速\t名詞,一般,*,*\nEOS")
}

///|
test "render_json should escape quote and backslash" {
  let out = render_json(
    [test_morpheme("\"\\\\", "未知語,記号,*,*", 0, 2)],
    @tok.EDITION_NANO,
  )
  assert_eq(
    out, "{\"edition\":\"nano\",\"tokens\":[{\"surface\":\"\\\"\\\\\\\\\",\"pos\":\"名詞,一般\",\"pos_detail\":\"未知語,記号,*,*\",\"start_pos\":0,\"end_pos\":2}]}",
  )
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
  let input = if options.text_from_args.length() > 0 {
    options.text_from_args
  } else {
    println("error: no input text")
    usage()
    return
  }
  let tokenizer = @tok.Tokenizer::new()
    .set_edition(options.edition)
    .set_use_lexmatch_scanner(options.use_lexmatch_scanner)
  let tokens = tokenizer.tokenize(input)
  match options.format {
    FORMAT_JSON => println(render_json(tokens, options.edition))
    FORMAT_WAKATI => println(render_wakati(tokens))
    _ => println(render_mecab(tokens))
  }
}
