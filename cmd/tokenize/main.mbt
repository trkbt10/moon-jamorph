///|
extern "c" fn c_getchar() -> Int = "getchar"

///|
type OutputMode = Int

///|
const OUTPUT_NONE = 0

///|
const OUTPUT_WAKATI = 1

///|
const OUTPUT_COUNT = 2

///|
struct CLIOptions {
  edition : Int
  output_mode : OutputMode
}

///|
fn read_stdin_utf8() -> String {
  let buf = @buffer.new(size_hint=1 << 20)
  while true {
    let ch = c_getchar()
    if ch < 0 {
      break
    }
    buf.write_byte(ch.to_byte())
  }
  @utf8.decode_lossy(buf.to_bytes()[:])
}

///|
fn usage() -> Unit {
  println("micado tokenize CLI")
  println("usage: cat input.txt | cmd/tokenize [options]")
  println("")
  println("options:")
  println("  -h, --help                   show this help")
  println(
    "  -e, --edition <name>         nano | mini | standard | full (compat; currently same behavior)",
  )
  println("  -O, --output <name>          none | count | wakati")
  println("")
  println("examples:")
  println(
    "  cat bench/corpus/aozora_openings.txt | moon run --target native cmd/tokenize -- -e full -O count",
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
  match name.to_lower() {
    "none" => OUTPUT_NONE
    "count" => OUTPUT_COUNT
    "wakati" => OUTPUT_WAKATI
    _ => -1
  }
}

///|
fn build_options(edition : Int, output_mode : OutputMode) -> CLIOptions {
  { edition, output_mode }
}

///|
fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
  let mut edition = @tok.EDITION_FULL
  let mut output_mode = OUTPUT_COUNT
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      return (build_options(edition, output_mode), None, true)
    }
    if arg == "-e" || arg == "--edition" {
      if i + 1 >= args.length() {
        return (
          build_options(edition, output_mode),
          Some("missing value for --edition"),
          false,
        )
      }
      let parsed = parse_edition_name(args[i + 1])
      if parsed < 0 {
        return (
          build_options(edition, output_mode),
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
    if arg == "-O" || arg == "--output" {
      if i + 1 >= args.length() {
        return (
          build_options(edition, output_mode),
          Some("missing value for --output"),
          false,
        )
      }
      let parsed = parse_output_mode(args[i + 1])
      if parsed < 0 {
        return (
          build_options(edition, output_mode),
          Some(
            "unknown output mode: \{args[i + 1]} (expected none|count|wakati)",
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
          build_options(edition, output_mode),
          Some("unknown output mode: \{value} (expected none|count|wakati)"),
          false,
        )
      }
      output_mode = parsed
      i = i + 1
      continue
    }
    return (
      build_options(edition, output_mode),
      Some("unknown option: \{arg}"),
      false,
    )
  }
  (build_options(edition, output_mode), None, false)
}

///|
fn split_non_empty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for raw in text.split("\n").map(StringView::to_string) {
    let line = raw.replace_all(old="\r", new="")
    if line.length() == 0 {
      continue
    }
    lines.push(line)
  }
  lines
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
  let input = read_stdin_utf8()
  let lines = split_non_empty_lines(input)
  if lines.length() == 0 {
    println("error: no input text from stdin")
    usage()
    return
  }
  let tokenizer = @tok.Tokenizer::new().set_edition(options.edition)
  let mut token_total = 0
  for line in lines {
    let tokens = tokenizer.tokenize(line)
    token_total = token_total + tokens.length()
    if options.output_mode == OUTPUT_WAKATI {
      println(tokens.map(token => token.surface).join(" "))
    }
  }
  if options.output_mode == OUTPUT_COUNT {
    println("sentences=\{lines.length()} tokens=\{token_total}")
  }
}
