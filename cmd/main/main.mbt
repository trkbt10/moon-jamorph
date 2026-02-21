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
  format : OutputFormat
  dictionary_source : String
  requested_dicdir : String?
  text_from_args : String
}

///|
struct OutputToken {
  surface : String
  pos : String
  pos_detail : String
  mecab_feature : String
  start_pos : Int
  end_pos : Int
}

///|
fn usage() -> Unit {
  println("micado CLI")
  println("usage: moon run cmd/main -- [options] [text]")
  println("")
  println("options:")
  println("  -h, --help                 show this help")
  println(
    "  -d, --dicdir <path>        use MeCab dictionary directory (required)",
  )
  println("  --dicdir <path>            same as -d")
  println("  -f, --format <name>        mecab | json | wakati")
  println("  -O <name> / -O<name>       MeCab-style output selector")
  println("  --json                     same as --format json")
  println("")
  println("input:")
  println("  Pass input text as positional arguments.")
  println("")
  println("examples:")
  println(
    "  moon run --target native cmd/main -- -d /opt/homebrew/lib/mecab/dic/ipadic -O mecab \"吾輩は猫である。\"",
  )
  println(
    "  moon run --target native cmd/main -- -d /opt/homebrew/lib/mecab/dic/unidic -O json \"太郎は走った。\"",
  )
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
fn parse_cli_args(args : Array[String]) -> (CLIOptions, String?, Bool) {
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
fn render_mecab(tokens : Array[OutputToken]) -> String {
  let lines = tokens.map(token => "\{token.surface}\t\{token.mecab_feature}")
  lines.push("EOS")
  lines.join("\n")
}

///|
fn trim_trailing_newlines(text : String) -> String {
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

///|
fn should_skip_mecab_dicdir_golden(err : String?) -> Bool {
  match err {
    Some(msg) =>
      msg.find("mecab dicdir backend is available only on native/llvm target")
      is Some(_)
    None => false
  }
}

///|
test "mecab unidic golden: 吾輩は猫である" {
  let input = "吾輩は猫である。名前はまだ無い。"
  let expected = [
    "吾輩\tワガハイ\tワガハイ\t我が輩\t代名詞\t\t", "は\tワ\tハ\tは\t助詞-係助詞\t\t",
    "猫\tネコ\tネコ\t猫\t名詞-普通名詞-一般\t\t", "で\tデ\tダ\tだ\t助動詞\t助動詞-ダ\t連用形-一般",
    "ある\tアル\tアル\t有る\t動詞-非自立可能\t五段-ラ行\t終止形-一般",
    "。\t\t\t。\t補助記号-句点\t\t", "名前\tナマエ\tナマエ\t名前\t名詞-普通名詞-一般\t\t",
    "は\tワ\tハ\tは\t助詞-係助詞\t\t", "まだ\tマダ\tマダ\t未だ\t副詞\t\t",
    "無い\tナイ\tナイ\t無い\t形容詞-非自立可能\t形容詞\t終止形-一般",
    "。\t\t\t。\t補助記号-句点\t\t", "EOS",
  ]
  let (out, err) = run_mecab_with_dicdir(
    input,
    "/opt/homebrew/lib/mecab/dic/unidic",
    FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(trim_trailing_newlines(out), expected.join("\n"))
}

///|
test "mecab unidic golden: メロスは激怒した" {
  let input = "メロスは激怒した。必ず、かの邪智暴虐の王を除かなければならぬと決意した。メロスには政治がわからぬ。"
  let expected = [
    "メロス\tメロス\tメロス\tメロス-melos\t名詞-普通名詞-一般\t\t",
    "は\tワ\tハ\tは\t助詞-係助詞\t\t", "激怒\tゲキド\tゲキド\t激怒\t名詞-普通名詞-サ変可能\t\t",
    "し\tシ\tスル\t為る\t動詞-非自立可能\tサ行変格\t連用形-一般",
    "た\tタ\tタ\tた\t助動詞\t助動詞-タ\t終止形-一般", "。\t\t\t。\t補助記号-句点\t\t",
    "必ず\tカナラズ\tカナラズ\t必ず\t副詞\t\t", "、\t\t\t、\t補助記号-読点\t\t",
    "かの\tカノ\tカノ\t彼の\t連体詞\t\t", "邪智\tジャチ\tジャチ\t邪知\t名詞-普通名詞-一般\t\t",
    "暴虐\tボーギャク\tボウギャク\t暴虐\t名詞-普通名詞-形状詞可能\t\t",
    "の\tノ\tノ\tの\t助詞-格助詞\t\t", "王\tオー\tオウ\t王\t名詞-普通名詞-一般\t\t",
    "を\tオ\tヲ\tを\t助詞-格助詞\t\t", "除か\tノゾカ\tノゾク\t除く\t動詞-一般\t五段-カ行\t未然形-一般",
    "なけれ\tナケレ\tナイ\tない\t助動詞\t助動詞-ナイ\t仮定形-一般",
    "ば\tバ\tバ\tば\t助詞-接続助詞\t\t", "なら\tナラ\tナル\t成る\t動詞-非自立可能\t五段-ラ行\t未然形-一般",
    "ぬ\tヌ\tズ\tず\t助動詞\t助動詞-ヌ\t終止形-一般", "と\tト\tト\tと\t助詞-格助詞\t\t",
    "決意\tケツイ\tケツイ\t決意\t名詞-普通名詞-サ変可能\t\t",
    "し\tシ\tスル\t為る\t動詞-非自立可能\tサ行変格\t連用形-一般",
    "た\tタ\tタ\tた\t助動詞\t助動詞-タ\t終止形-一般", "。\t\t\t。\t補助記号-句点\t\t",
    "メロス\tメロス\tメロス\tメロス-melos\t名詞-普通名詞-一般\t\t",
    "に\tニ\tニ\tに\t助詞-格助詞\t\t", "は\tワ\tハ\tは\t助詞-係助詞\t\t",
    "政治\tセージ\tセイジ\t政治\t名詞-普通名詞-一般\t\t", "が\tガ\tガ\tが\t助詞-格助詞\t\t",
    "わから\tワカラ\tワカル\t分かる\t動詞-一般\t五段-ラ行\t未然形-一般",
    "ぬ\tヌ\tズ\tず\t助動詞\t助動詞-ヌ\t終止形-一般", "。\t\t\t。\t補助記号-句点\t\t",
    "EOS",
  ]
  let (out, err) = run_mecab_with_dicdir(
    input,
    "/opt/homebrew/lib/mecab/dic/unidic",
    FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(trim_trailing_newlines(out), expected.join("\n"))
}

///|
test "mecab unidic golden: 春はあけぼの" {
  let input = "春はあけぼの。やうやう白くなりゆく山ぎは、少しあかりて、紫だちたる雲の細くたなびきたる。"
  let expected = [
    "春\tハル\tハル\t春\t名詞-普通名詞-副詞可能\t\t", "は\tワ\tハ\tは\t助詞-係助詞\t\t",
    "あけぼの\tアケボノ\tアケボノ\t曙\t名詞-普通名詞-一般\t\t",
    "。\t\t\t。\t補助記号-句点\t\t", "やう\tヨー\tヨウ\t様\t形状詞-助動詞語幹\t\t",
    "やう\tヨー\tヨウ\t様\t形状詞-助動詞語幹\t\t", "白く\tシロク\tシロイ\t白い\t形容詞-一般\t形容詞\t連用形-一般",
    "なり\tナリ\tナル\t成る\t動詞-非自立可能\t五段-ラ行\t連用形-一般",
    "ゆく\tユク\tイク\t行く\t動詞-非自立可能\t五段-カ行\t連体形-一般",
    "山ぎは\tヤマギワ\tヤマギワ\t山際\t名詞-普通名詞-一般\t\t",
    "、\t\t\t、\t補助記号-読点\t\t", "少し\tスコシ\tスコシ\t少し\t副詞\t\t",
    "あ\tア\tアー\tあー\t感動詞-フィラー\t\t", "かり\tカリ\tカリル\t借りる\t動詞-一般\t上一段-ラ行\t連用形-一般",
    "て\tテ\tテ\tて\t助詞-接続助詞\t\t", "、\t\t\t、\t補助記号-読点\t\t",
    "紫だち\tムラサキダチ\tムラサキダツ\t紫立つ\t動詞-一般\t五段-タ行\t連用形-一般",
    "たる\tタル\tタリ\tたり-断定\t助動詞\t文語助動詞-タリ-断定\t連体形-一般",
    "雲\tクモ\tクモ\t雲\t名詞-普通名詞-一般\t\t", "の\tノ\tノ\tの\t助詞-格助詞\t\t",
    "細く\tホソク\tホソイ\t細い\t形容詞-一般\t形容詞\t連用形-一般",
    "たなびき\tタナビキ\tタナビク\t棚引く\t動詞-一般\t五段-カ行\t連用形-一般",
    "たる\tタル\tタリ\tたり-断定\t助動詞\t文語助動詞-タリ-断定\t連体形-一般",
    "。\t\t\t。\t補助記号-句点\t\t", "EOS",
  ]
  let (out, err) = run_mecab_with_dicdir(
    input,
    "/opt/homebrew/lib/mecab/dic/unidic",
    FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(trim_trailing_newlines(out), expected.join("\n"))
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
  let dicdir = match options.requested_dicdir {
    Some(path) => path
    None => {
      println("error: --dicdir is required")
      usage()
      return
    }
  }
  let (stdout, run_error) = run_mecab_with_dicdir(input, dicdir, options.format)
  if run_error is Some(msg) {
    println("error: \{msg}")
    if stdout.length() > 0 {
      println(trim_trailing_newlines(stdout))
    }
    return
  }
  if options.format == FORMAT_JSON {
    let tokens = parse_mecab_output_tokens(stdout)
    println(render_json(tokens, options))
  } else {
    println(trim_trailing_newlines(stdout))
  }
}
