///|
fn main {
  let _ = @env.args()
  let _ = @buffer.new()
  let _ = @utf8.encode(""[:])
  let _ = @compiler.compile_tsv_to_da_trie_module_for_edition(
    "", "stub", "standard",
  )
  println(
    "tools/dict-compiler/cmd/emit_da is only supported on native/llvm target",
  )
}
