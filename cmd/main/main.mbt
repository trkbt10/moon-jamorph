///|
fn usage() -> Unit {
  for line in @mecab_cli.usage_lines() {
    println(line)
  }
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
    @mecab_cli.FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(@mecab_cli.trim_trailing_newlines(out), expected.join("\n"))
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
    @mecab_cli.FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(@mecab_cli.trim_trailing_newlines(out), expected.join("\n"))
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
    @mecab_cli.FORMAT_MECAB,
  )
  if should_skip_mecab_dicdir_golden(err) {
    inspect(true, content="true")
    return
  }
  inspect(err, content="None")
  assert_eq(@mecab_cli.trim_trailing_newlines(out), expected.join("\n"))
}

///|
fn main {
  let args = @env.args()
  let (options, error, show_help) = @mecab_cli.parse_cli_args(args)
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
      println(@mecab_cli.trim_trailing_newlines(stdout))
    }
    return
  }
  if options.format == @mecab_cli.FORMAT_JSON {
    println(@mecab_cli.render_json_from_mecab_output(stdout, options))
  } else {
    println(@mecab_cli.trim_trailing_newlines(stdout))
  }
}
