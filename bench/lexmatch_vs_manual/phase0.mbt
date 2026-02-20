///|
pub fn benchmark_scanner(input : String, count? : UInt = 1000U) -> String {
  let bencher = @bench.new()
  bencher.bench(name="scanner_manual", count~, fn() {
    bencher.keep(@scanner.scan_char_classes_manual(input))
  })
  bencher.bench(name="scanner_lexmatch", count~, fn() {
    bencher.keep(@scanner.scan_char_classes_lexmatch(input))
  })
  bencher.dump_summaries()
}
