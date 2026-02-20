///|
extern "c" fn c_popen(cmd : Bytes, mode : Bytes) -> Int64 = "popen"

///|
extern "c" fn c_fgetc(fp : Int64) -> Int = "fgetc"

///|
extern "c" fn c_pclose(fp : Int64) -> Int = "pclose"

///|
fn shell_quote_single(raw : String) -> String {
  let replacement = "'\"'\"'"
  let escaped = raw.replace_all(old="'", new=replacement)
  "'\{escaped}'"
}

///|
fn has_line(input : String, needle : String) -> Bool {
  for line in input.split("\n").map(StringView::to_string) {
    if line == needle {
      return true
    }
  }
  false
}

///|
fn choose_heredoc_delim(input : String) -> String {
  let mut delim = "__MICADO_INPUT__"
  let mut i = 0
  while has_line(input, delim) {
    i = i + 1
    delim = "__MICADO_INPUT_\{i}__"
  }
  delim
}

///|
fn build_mecab_shell_command(
  input : String,
  dicdir : String,
  format : OutputFormat,
) -> String {
  let delim = choose_heredoc_delim(input)
  let dicdir_q = shell_quote_single(dicdir)
  let mecab_cmd = match format {
    x if x == FORMAT_WAKATI => "mecab -O wakati -d \{dicdir_q}"
    _ => "mecab -d \{dicdir_q}"
  }
  "cat <<'\{delim}' | \{mecab_cmd}\n\{input}\n\{delim}\n"
}

///|
fn to_c_string(text : String) -> Bytes {
  let encoded = @utf8.encode(text[:])
  let buf = @buffer.new(size_hint=encoded.length() + 1)
  buf.write_bytes(encoded)
  buf.write_byte(0)
  buf.to_bytes()
}

///|
fn run_shell_capture_utf8(command : String) -> (String, Int) {
  let fp = c_popen(to_c_string(command), to_c_string("r"))
  if fp == 0 {
    return ("", -1)
  }
  let out = @buffer.new(size_hint=1 << 14)
  while true {
    let ch = c_fgetc(fp)
    if ch < 0 {
      break
    }
    out.write_byte(ch.to_byte())
  }
  let status = c_pclose(fp)
  (@utf8.decode_lossy(out.to_bytes()[:]), status)
}

///|
fn run_mecab_with_dicdir(
  input : String,
  dicdir : String,
  format : OutputFormat,
) -> (String, String?) {
  let command = build_mecab_shell_command(input, dicdir, format)
  let (stdout, status) = run_shell_capture_utf8(command)
  if status != 0 {
    return (stdout, Some("mecab command failed (status=\{status})"))
  }
  (stdout, None)
}
