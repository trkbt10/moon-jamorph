///|
extern "c" fn c_getchar() -> Int = "getchar"

///|
fn read_stdin_utf8() -> String {
  let buf = @buffer.new(size_hint=1 << 20)
  while true {
    let ch = c_getchar()
    if ch < 0 {
      break
    }
    buf.write_byte(ch.to_byte())
  }
  @utf8.decode_lossy(buf.to_bytes()[:])
}

///|
fn usage() -> Unit {
  println(
    "usage: moon run tools/dict-compiler/cmd/emit_da -- <symbol_prefix> <edition>",
  )
}

///|
fn main {
  let args = @env.args()
  if args.length() < 3 {
    usage()
    return
  }
  let symbol_prefix = args[args.length() - 2]
  let edition = args[args.length() - 1]
  let tsv = read_stdin_utf8()
  let out = @compiler.compile_tsv_to_da_trie_module_for_edition(
    tsv, symbol_prefix, edition,
  )
  println(out)
}
