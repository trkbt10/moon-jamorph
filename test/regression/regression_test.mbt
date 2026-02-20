///|
fn _keep_imports_alive_regression() -> Unit {
  let _ = @tok.EDITION_NANO
  let _ = @scanner.scanner_modes_match("")
  let bytes = @utf8.encode(""[:])
  let _ = @scanner8.scanner_modes_match_utf8(bytes[:])
  let _ = @bench0.benchmark_scanner("", count=0U)
  let _ = @bench4.benchmark_tokenizer_throughput("", count=0U)

}

///|
test "scanner manual and lexmatch should match on basic sentence" {
  inspect(@scanner.scanner_modes_match("すももABC123!?"), content="true")
}

///|
test "scanner should compute class run lengths" {
  let classes = @scanner.scan_char_classes_manual("ああA!!")
  let runs = @scanner.compute_class_run_lengths(classes)
  inspect(runs, content="[2, 1, 1, 2, 1]")
}

///|
test "scanner manual with run lengths should match expected classes" {
  let (classes, runs) = @scanner.scan_char_classes_manual_chars_with_run_lengths(
    "ああA!!".to_array(),
  )
  inspect(classes, content="[Hiragana, Hiragana, AsciiAlpha, Symbol, Symbol]")
  inspect(runs, content="[2, 1, 1, 2, 1]")
}

///|
test "scanner lexmatch with run lengths should match expected classes" {
  let (classes, runs) = @scanner.scan_char_classes_lexmatch_chars_with_run_lengths(
    "ああA!!".to_array(),
  )
  inspect(classes, content="[Hiragana, Hiragana, AsciiAlpha, Symbol, Symbol]")
  inspect(runs, content="[2, 1, 1, 2, 1]")
}

///|
test "utf8 scanner manual with run lengths should detect run boundaries" {
  let bytes = @utf8.encode("aaああ!!"[:])
  let (classes, runs) = @scanner8.scan_char_classes_manual_utf8_with_run_lengths(
    bytes[:],
  )
  inspect(
    classes,
    content="[AsciiAlpha, AsciiAlpha, Hiragana, Hiragana, Symbol, Symbol]",
  )
  inspect(runs, content="[2, 1, 2, 1, 2, 1]")
}

///|
test "utf8 scanner run lengths should handle astral emoji run" {
  let bytes = @utf8.encode("a🤣🤣b"[:])
  let (classes, runs) = @scanner8.scan_char_classes_manual_utf8_with_run_lengths(
    bytes[:],
  )
  inspect(classes, content="[AsciiAlpha, Other, Other, AsciiAlpha]")
  inspect(runs, content="[1, 2, 1, 1]")
}

///|
test "tokenize should parse sumomo sentence with viterbi" {
  let tokens = @tok.tokenize("すもももももももものうち")
  inspect(
    tokens.map(t => t.surface),
    content="[\"すもも\", \"も\", \"もも\", \"も\", \"もも\", \"の\", \"うち\"]",
  )
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,一般,*,*\", \"助詞,係助詞,*,*\", \"名詞,一般,*,*\", \"助詞,係助詞,*,*\", \"名詞,一般,*,*\", \"助詞,連体化,*,*\", \"名詞,非自立,副詞可能,*\"]",
  )
}

///|
test "tokenize should fallback to unknown nodes" {
  let tokens = @tok.tokenize("abc")
  inspect(tokens.map(t => t.surface), content="[\"abc\"]")
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,未知語,*\"]",
  )
}

///|
test "tokenizer options should be composable" {
  let t1 = @tok.Tokenizer::new()
    .set_edition(@tok.EDITION_MINI)
    .set_mode(@tok.MODE_SEARCH)
    .set_use_lexmatch_scanner(true)
  let t2 = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let t3 = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  inspect(
    t1.tokenize("すもももももももものうち").length() > 0,
    content="true",
  )
  inspect(
    t2.tokenize("すもももももももものうち").length() > 0,
    content="true",
  )
  inspect(
    t3.tokenize("すもももももももものうち").length() > 0,
    content="true",
  )
}

///|
test "lexmatch scanner should match manual on mixed boundaries" {
  let manual = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let lex = @tok.Tokenizer::new()
    .set_edition(@tok.EDITION_STANDARD)
    .set_use_lexmatch_scanner(true)
  let text = "abc!!123🤣かな"
  let m = manual.tokenize(text)
  let l = lex.tokenize(text)
  assert_eq(l.map(t => t.surface), m.map(t => t.surface))
  assert_eq(l.map(t => t.pos_detail), m.map(t => t.pos_detail))
}

///|
test "lexmatch scanner should match manual on utf8 mixed boundaries" {
  let manual = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let lex = @tok.Tokenizer::new()
    .set_edition(@tok.EDITION_STANDARD)
    .set_use_lexmatch_scanner(true)
  let bytes = @utf8.encode("abc!!123🤣かな"[:])
  let m = manual.tokenize_utf8(bytes[:])
  let l = lex.tokenize_utf8(bytes[:])
  assert_eq(l.map(t => t.surface), m.map(t => t.surface))
  assert_eq(l.map(t => t.pos_detail), m.map(t => t.pos_detail))
}

///|
test "lexmatch scanner should match manual on long mixed utf16 boundaries" {
  let manual = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let lex = @tok.Tokenizer::new()
    .set_edition(@tok.EDITION_FULL)
    .set_use_lexmatch_scanner(true)
  let text = "#AirPods!!東京大学abc123🤣かなXYZ"
  let m = manual.tokenize(text)
  let l = lex.tokenize(text)
  assert_eq(l.map(t => t.surface), m.map(t => t.surface))
  assert_eq(l.map(t => t.pos_detail), m.map(t => t.pos_detail))
}

///|
test "lexmatch scanner should match manual on long mixed utf8 boundaries" {
  let manual = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let lex = @tok.Tokenizer::new()
    .set_edition(@tok.EDITION_FULL)
    .set_use_lexmatch_scanner(true)
  let bytes = @utf8.encode("#AirPods!!東京大学abc123🤣かなXYZ"[:])
  let m = manual.tokenize_utf8(bytes[:])
  let l = lex.tokenize_utf8(bytes[:])
  assert_eq(l.map(t => t.surface), m.map(t => t.surface))
  assert_eq(l.map(t => t.pos_detail), m.map(t => t.pos_detail))
}

///|
test "edition should change dictionary coverage" {
  let nano = @tok.Tokenizer::new().set_edition(@tok.EDITION_NANO)
  let mini = @tok.Tokenizer::new().set_edition(@tok.EDITION_MINI)
  let standard = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  inspect(
    nano.tokenize("東京大学").map(t => t.surface),
    content="[\"東京大学\"]",
  )
  inspect(
    mini.tokenize("東京大学").map(t => t.surface),
    content="[\"東京\", \"大学\"]",
  )
  inspect(
    standard.tokenize("東京都大学院").map(t => t.surface),
    content="[\"東京都\", \"大学院\"]",
  )
}

///|
test "full edition should preserve detailed pos from neologd" {
  let full = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let tokens = full.tokenize("!Wagero!")
  inspect(tokens.map(t => t.surface), content="[\"!Wagero!\"]")
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,人名,一般\"]",
  )
}

///|
test "standard edition should expose detailed pos from ipadic" {
  let standard = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let tokens = standard.tokenize("迅速")
  inspect(tokens.map(t => t.surface), content="[\"迅速\"]")
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,形容動詞語幹,*,*\"]",
  )
}

///|
test "utf8 scanner manual and lexmatch should match on basic input" {
  let bytes = @utf8.encode("すももABC123!?"[:])
  inspect(@scanner8.scanner_modes_match_utf8(bytes[:]), content="true")
}

///|
test "tokenizer should accept utf8 bytes input" {
  let full = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let bytes = @utf8.encode("!Wagero!"[:])
  let tokens = full.tokenize_utf8(bytes[:])
  inspect(tokens.map(t => t.surface), content="[\"!Wagero!\"]")
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,人名,一般\"]",
  )
}

///|
test "full tokenizer should keep hashtag lexeme as one token" {
  let full = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let tokens = full.tokenize("#AirPodsを買う")
  inspect(
    tokens.map(t => t.surface),
    content="[\"#AirPods\", \"を\", \"買\", \"う\"]",
  )
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,一般,*\", \"未知語,ひらがな,*,*\", \"名詞,一般,未知語,*\", \"未知語,ひらがな,*,*\"]",
  )
}

///|
test "tokenize should preserve astral emoji surface boundaries" {
  let tokens = @tok.tokenize("A🤣B")
  inspect(tokens.map(t => t.surface), content="[\"A\", \"🤣\", \"B\"]")
}

///|
test "tokenize_utf8 should preserve astral emoji surface boundaries" {
  let bytes = @utf8.encode("A🤣B"[:])
  let tokens = @tok.tokenize_utf8(bytes[:])
  inspect(tokens.map(t => t.surface), content="[\"A\", \"🤣\", \"B\"]")
}

///|
#skip("benchmark smoke test")
test "phase0 benchmark smoke" {
  let report = @bench0.benchmark_scanner(
    "すもももももももものうち",
    count=100U,
  )
  inspect(report.length() > 0, content="true")
}

///|
#skip("benchmark smoke test")
test "phase4 throughput benchmark smoke" {
  let report = @bench4.benchmark_tokenizer_throughput(
    "すもももももももものうち東京大学東京都大学院",
    count=100U,
  )
  inspect(report.length() > 0, content="true")
}
