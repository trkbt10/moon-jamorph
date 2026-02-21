///|
fn main {
  let _ = @tok.EDITION_FULL
  let _ = @types.ParseOptions::default()
  println("error: cmd/tokenize is available only on native/llvm target")
}
