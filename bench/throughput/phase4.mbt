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

///|
pub fn benchmark_tokenizer_constraints_nbest(
  input : String,
  count? : UInt = 500U,
) -> String {
  let bencher = @bench.new()
  let tok = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let options_default : @types.ParseOptions = @types.ParseOptions::default()
  let options_break : @types.ParseOptions = {
    constraint: { ..@types.ParseConstraint::none(), must_break_positions: [1] },
  }
  bencher.bench(name="tokenize_standard", count~, fn() {
    bencher.keep(tok.tokenize(input))
  })
  bencher.bench(name="tokenize_with_options_default", count~, fn() {
    bencher.keep(tok.tokenize_with_options(input, options_default))
  })
  bencher.bench(name="tokenize_with_options_break", count~, fn() {
    bencher.keep(tok.tokenize_with_options(input, options_break))
  })
  bencher.bench(name="tokenize_nbest_3", count~, fn() {
    bencher.keep(tok.tokenize_nbest(input, 3))
  })
  bencher.dump_summaries()
}
