///|
fn main {
  let _ = @tok.EDITION_FULL
  let (opts, _, _) = parse_cli_args(["cmd/tokenize"])
  let _ = build_parse_options(opts)
  let _ = opts.edition
  let _ = opts.output_mode
  let _ = opts.dicdir
  let _ = opts.nbest
  println("error: cmd/tokenize is available only on native/llvm target")
}
