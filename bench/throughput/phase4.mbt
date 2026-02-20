///|
pub fn benchmark_tokenizer_throughput(
  input : String,
  count? : UInt = 1000U,
) -> String {
  let bencher = @bench.new()
  bencher.bench(name="tokenize_nano", count~, fn() {
    bencher.keep(
      @tok.Tokenizer::new().set_edition(@tok.EDITION_NANO).tokenize(input),
    )
  })
  bencher.bench(name="tokenize_mini", count~, fn() {
    bencher.keep(
      @tok.Tokenizer::new().set_edition(@tok.EDITION_MINI).tokenize(input),
    )
  })
  bencher.bench(name="tokenize_standard", count~, fn() {
    bencher.keep(
      @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD).tokenize(input),
    )
  })
  bencher.dump_summaries()
}
