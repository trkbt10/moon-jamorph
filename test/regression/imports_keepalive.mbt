///|
pub fn keepalive_regression_imports() -> Unit {
  let _ = @tok.EDITION_NANO
  let _ = @tok.Tokenizer::new()
  let _ = @scanner.scanner_modes_match("")
  let bytes = @utf8.encode(""[:])
  let _ = @scanner8.scanner_modes_match_utf8(bytes[:])
  let _ = @bench0.benchmark_scanner("", count=0U)
  let _ = @bench4.benchmark_tokenizer_throughput("", count=0U)

}
