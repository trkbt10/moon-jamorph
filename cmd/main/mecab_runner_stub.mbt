///|
fn run_mecab_with_dicdir(
  _input : String,
  _dicdir : String,
  _format : OutputFormat,
) -> (String, String?) {
  let _ = @buffer.new(size_hint=0)
  (
    "",
    Some(
      "mecab dicdir backend is available only on native/llvm target (run with --target native)",
    ),
  )
}
