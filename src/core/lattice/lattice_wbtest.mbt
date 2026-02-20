///|
test "candidates_at wrapper should preserve unknown run length behavior" {
  let chars = "abc".to_array()
  let classes = [
    @types.CharClass::AsciiAlpha,
    @types.CharClass::AsciiAlpha,
    @types.CharClass::AsciiAlpha,
  ]
  let cands = candidates_at(chars, classes, 0, 0)
  inspect(cands.map(c => c.end_pos), content="[3, 1]")
}
