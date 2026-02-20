///|
fn contains_char(xs : Array[Char], value : Char) -> Bool {
  for x in xs {
    if x == value {
      return true
    }
  }
  false
}

///|
pub fn distinct_first_chars(surfaces : Array[String]) -> Array[Char] {
  let chars = Array::new()
  for surface in surfaces {
    let arr = surface.to_array()
    if arr.length() == 0 {
      continue
    }
    let head = arr[0]
    if !contains_char(chars, head) {
      chars.push(head)
    }
  }
  chars
}

///|
pub fn first_char_count(surfaces : Array[String]) -> Int {
  distinct_first_chars(surfaces).length()
}
