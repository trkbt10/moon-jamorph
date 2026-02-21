///|
pub type OutputFormat = Int

///|
pub const FORMAT_MECAB : OutputFormat = 0

///|
pub const FORMAT_JSON : OutputFormat = 1

///|
pub const FORMAT_WAKATI : OutputFormat = 2

///|
pub(all) struct CLIOptions {
  format : OutputFormat
  dictionary_source : String
  requested_dicdir : String?
  text_from_args : String
}

///|
priv struct OutputToken {
  surface : String
  pos : String
  pos_detail : String
  mecab_feature : String
  start_pos : Int
  end_pos : Int
}

///|
pub fn usage_lines() -> Array[String] {
  [
    "micado CLI", "usage: moon run cmd/main -- [options] [text]", "", "options:",
    "  -h, --help                 show this help", "  -d, --dicdir <path>        use MeCab dictionary directory (required)",
    "  --dicdir <path>            same as -d", "  -f, --format <name>        mecab | json | wakati",
    "  -O <name> / -O<name>       MeCab-style output selector", "  --json                     same as --format json",
    "", "input:", "  Pass input text as positional arguments.", "", "examples:",
    "  moon run --target native cmd/main -- -d /opt/homebrew/lib/mecab/dic/ipadic -O mecab \"吾輩は猫である。\"",
    "  moon run --target native cmd/main -- -d /opt/homebrew/lib/mecab/dic/unidic -O json \"太郎は走った。\"",
  ]
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
fn build_cli_options(
  format : OutputFormat,
  requested_dicdir : String?,
  text_parts : Array[String],
) -> CLIOptions {
  {
    format,
    dictionary_source: "dicdir",
    requested_dicdir,
    text_from_args: text_parts.join(" "),
  }
}

///|
pub fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
  let mut format = FORMAT_MECAB
  let mut requested_dicdir : String? = None
  let text_parts : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      let options = build_cli_options(format, requested_dicdir, text_parts)
      return (options, None, true)
    }
    if arg == "--json" {
      format = FORMAT_JSON
      i = i + 1
      continue
    }
    if arg == "--" {
      for j in (i + 1)..<args.length() {
        text_parts.push(args[j])
      }
      break
    }
    if arg == "-d" || arg == "--dicdir" {
      if i + 1 >= args.length() {
        let options = build_cli_options(format, requested_dicdir, text_parts)
        return (options, Some("missing value for --dicdir"), false)
      }
      requested_dicdir = Some(args[i + 1])
      i = i + 2
      continue
    }
    if arg == "-f" || arg == "--format" || arg == "-O" {
      if i + 1 >= args.length() {
        let options = build_cli_options(format, requested_dicdir, text_parts)
        return (options, Some("missing value for --format"), false)
      }
      let parsed = parse_format_name(args[i + 1])
      if parsed < 0 {
        let options = build_cli_options(format, requested_dicdir, text_parts)
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
        let options = build_cli_options(format, requested_dicdir, text_parts)
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
      let options = build_cli_options(format, requested_dicdir, text_parts)
      return (options, Some("unknown option: \{arg}"), false)
    }
    text_parts.push(arg)
    i = i + 1
  }
  let options = build_cli_options(format, requested_dicdir, text_parts)
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
fn feature_col_or_star(cols : Array[String], index : Int) -> String {
  if index < cols.length() {
    cols[index]
  } else {
    "*"
  }
}

///|
fn join_from(cols : Array[String], start : Int, sep : String) -> String {
  if start >= cols.length() {
    return ""
  }
  let b = StringBuilder::new(size_hint=32)
  for i in start..<cols.length() {
    if i > start {
      b.write_string(sep)
    }
    b.write_string(cols[i])
  }
  b.to_string()
}

///|
fn parse_pos_and_detail(feature : String) -> (String, String) {
  let tab_cols = feature.split("\t").map(StringView::to_string).collect()
  if tab_cols.length() >= 4 {
    let pos = feature_col_or_star(tab_cols, 3)
    return (pos, pos)
  }
  let cols = feature.split(",").map(StringView::to_string).collect()
  let pos = "\{feature_col_or_star(cols, 0)},\{feature_col_or_star(cols, 1)}"
  let detail = "\{feature_col_or_star(cols, 0)},\{feature_col_or_star(cols, 1)},\{feature_col_or_star(cols, 2)},\{feature_col_or_star(cols, 3)}"
  (pos, detail)
}

///|
fn parse_mecab_output_tokens(output : String) -> Array[OutputToken] {
  let tokens : Array[OutputToken] = []
  let mut cursor = 0
  for raw_line in output.split("\n").map(StringView::to_string) {
    let line = raw_line.replace_all(old="\r", new="")
    if line.length() == 0 || line == "EOS" {
      continue
    }
    let cols = line.split("\t").map(StringView::to_string).collect()
    if cols.length() == 0 {
      continue
    }
    let surface = cols[0]
    let feature = if cols.length() >= 2 {
      join_from(cols, 1, "\t")
    } else {
      "*,*,*,*,*,*,*,*,*"
    }
    let (pos, pos_detail) = parse_pos_and_detail(feature)
    let start_pos = cursor
    let end_pos = cursor + surface.char_length()
    cursor = end_pos
    tokens.push({
      surface,
      pos,
      pos_detail,
      mecab_feature: feature,
      start_pos,
      end_pos,
    })
  }
  tokens
}

///|
fn render_json(tokens : Array[OutputToken], options : CLIOptions) -> String {
  let b = StringBuilder::new(size_hint=tokens.length() * 100 + 160)
  b.write_char('{')
  append_json_string_field(b, "backend", "mecab")
  b.write_char(',')
  append_json_string_field(b, "dictionary_source", options.dictionary_source)
  if options.requested_dicdir is Some(dicdir) {
    b.write_char(',')
    append_json_string_field(b, "requested_dicdir", dicdir)
  }
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
    append_json_string_field(b, "pos", token.pos)
    b.write_char(',')
    append_json_string_field(b, "pos_detail", token.pos_detail)
    b.write_char(',')
    append_json_string_field(b, "mecab_feature", token.mecab_feature)
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
pub fn render_json_from_mecab_output(
  output : String,
  options : CLIOptions,
) -> String {
  render_json(parse_mecab_output_tokens(output), options)
}

///|
fn render_mecab(tokens : Array[OutputToken]) -> String {
  let lines = tokens.map(token => "\{token.surface}\t\{token.mecab_feature}")
  lines.push("EOS")
  lines.join("\n")
}

///|
pub fn trim_trailing_newlines(text : String) -> String {
  let mut end = text.length()
  while end > 0 {
    let c = text.unsafe_get(end - 1)
    if c == '\n' || c == '\r' {
      end = end - 1
    } else {
      break
    }
  }
  if end == text.length() {
    text
  } else {
    text.unsafe_substring(start=0, end~)
  }
}

///|
fn test_output_token(
  surface : String,
  pos : String,
  pos_detail : String,
  mecab_feature : String,
  start_pos : Int,
  end_pos : Int,
) -> OutputToken {
  { surface, pos, pos_detail, mecab_feature, start_pos, end_pos }
}

///|
test "cli parse should accept mecab compatible options" {
  let (options, error, show_help) = parse_cli_args([
    "cmd/main", "-d", "/opt/homebrew/lib/mecab/dic/unidic", "-Ojson", "迅速",
  ])
  inspect(show_help, content="false")
  inspect(error, content="None")
  inspect(options.dictionary_source, content="dicdir")
  inspect(
    options.requested_dicdir,
    content="Some(\"/opt/homebrew/lib/mecab/dic/unidic\")",
  )
  inspect(options.format, content="1")
  inspect(options.text_from_args, content="迅速")
}

///|
test "cli parse should treat dicdir path as mecab backend" {
  let (options, error, show_help) = parse_cli_args([
    "cmd/main", "-d", "/opt/homebrew/lib/mecab/dic/unidic", "-O", "mecab", "東京",
  ])
  inspect(show_help, content="false")
  inspect(error, content="None")
  inspect(options.dictionary_source, content="dicdir")
  inspect(
    options.requested_dicdir,
    content="Some(\"/opt/homebrew/lib/mecab/dic/unidic\")",
  )
}

///|
test "parse_mecab_output_tokens should keep verb and particle detail" {
  let sample = "走っ\t動詞,自立,*,*,五段・ラ行,連用タ接続,走る,ハシッ,ハシッ\nた\t助動詞,*,*,*,特殊・タ,基本形,た,タ,タ\n。\t記号,句点,*,*,*,*,。,。,。\nEOS\n"
  let tokens = parse_mecab_output_tokens(sample)
  inspect(tokens.length(), content="3")
  inspect(tokens[0].pos, content="動詞,自立")
  inspect(tokens[0].pos_detail, content="動詞,自立,*,*")
  inspect(tokens[1].pos, content="助動詞,*")
}

///|
test "render_mecab should include EOS line" {
  let out = render_mecab([
    test_output_token(
      "迅速", "名詞,一般", "名詞,一般,*,*", "名詞,一般,*,*,*,*,迅速,ジンソク,ジンソク",
      0, 2,
    ),
  ])
  assert_eq(
    out, "迅速\t名詞,一般,*,*,*,*,迅速,ジンソク,ジンソク\nEOS",
  )
}

///|
test "render_json should escape quote and backslash" {
  let options : CLIOptions = {
    format: FORMAT_JSON,
    dictionary_source: "dicdir",
    requested_dicdir: Some("/opt/homebrew/lib/mecab/dic/ipadic"),
    text_from_args: "",
  }
  let out = render_json(
    [
      test_output_token(
        "\"\\", "名詞,一般", "未知語,記号,*,*", "未知語,記号,*,*,*,*,*,*,*",
        0, 2,
      ),
    ],
    options,
  )
  assert_eq(
    out, "{\"backend\":\"mecab\",\"dictionary_source\":\"dicdir\",\"requested_dicdir\":\"/opt/homebrew/lib/mecab/dic/ipadic\",\"tokens\":[{\"surface\":\"\\\"\\\\\",\"pos\":\"名詞,一般\",\"pos_detail\":\"未知語,記号,*,*\",\"mecab_feature\":\"未知語,記号,*,*,*,*,*,*,*\",\"start_pos\":0,\"end_pos\":2}]}",
  )
}

///|
test "parse_mecab_output_tokens should parse unidic tab-style feature" {
  let sample = "太郎\tタロー\tタロウ\tタロウ\t名詞-固有名詞-人名-名\t\t\nEOS\n"
  let tokens = parse_mecab_output_tokens(sample)
  inspect(tokens.length(), content="1")
  inspect(tokens[0].pos, content="名詞-固有名詞-人名-名")
  inspect(tokens[0].mecab_feature.find("\t") is Some(_), content="true")
}
