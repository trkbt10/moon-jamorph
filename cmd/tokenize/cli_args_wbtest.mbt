///|
test "parse_cli_args should default to mecab output" {
  let (opts, err, help) = parse_cli_args(["cmd/tokenize"])
  inspect(err, content="None")
  inspect(help, content="false")
  assert_eq(opts.output_mode, OUTPUT_MECAB)
  assert_eq(opts.nbest, 1)
  assert_eq(opts.edition, @tok.EDITION_FULL)
}

///|
test "parse_cli_args should accept mecab-compatible long forms" {
  let (opts, err, help) = parse_cli_args([
    "cmd/tokenize", "--output-format-type=wakati", "--nbest=3", "--dicdir=/tmp/a",
    "-d", "/tmp/b",
  ])
  inspect(err, content="None")
  inspect(help, content="false")
  assert_eq(opts.output_mode, OUTPUT_WAKATI)
  assert_eq(opts.nbest, 3)
  match opts.dicdir {
    Some(path) => inspect(path, content="/tmp/b")
    None => assert_true(false)
  }
}

///|
test "parse_cli_args should parse constraint extensions" {
  let (opts, err, help) = parse_cli_args([
    "cmd/tokenize", "-N2", "-Ocount", "--no-unknown", "--must-break", "1,3", "--forbid-break",
    "2", "--must-cover-span", "0:1,1:2", "--allow-pos", "noun-general,particle",
    "--disallow-pos", "unknown",
  ])
  inspect(err, content="None")
  inspect(help, content="false")
  assert_eq(opts.output_mode, OUTPUT_COUNT)
  assert_eq(opts.nbest, 2)
  assert_eq(opts.allow_unknown, false)
  inspect(opts.must_break_positions, content="[1, 3]")
  inspect(opts.forbid_break_positions, content="[2]")
  inspect(
    opts.must_cover_spans.map(span => "\{span.start_pos}:\{span.end_pos}"),
    content="[\"0:1\", \"1:2\"]",
  )
  inspect(opts.allowed_pos, content="[NounGeneral, Particle]")
  inspect(opts.disallowed_pos, content="[Unknown]")
}

///|
test "parse_cli_args should reject invalid values" {
  let (_, err_output, _) = parse_cli_args([
    "cmd/tokenize", "--output-format-type=bad",
  ])
  inspect(
    err_output,
    content="Some(\"unknown output mode: bad (expected mecab|wakati|none|count)\")",
  )
  let (_, err_nbest, _) = parse_cli_args(["cmd/tokenize", "--nbest=0"])
  inspect(
    err_nbest,
    content="Some(\"invalid --nbest value: 0 (expected positive integer)\")",
  )
}
