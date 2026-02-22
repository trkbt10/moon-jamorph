///|
/// MeCab matrix.bin parser
///
/// Binary structure:
/// - Header: lsize (2 bytes), rsize (2 bytes)
/// - Matrix: lsize * rsize * 2 bytes (int16 costs)

///|
/// Parsed connection cost matrix
pub struct MecabMatrix {
  lsize : Int  // left context size (number of right_attr values)
  rsize : Int  // right context size (number of left_attr values)
  costs : Array[Int]  // flattened matrix [right_attr * lsize + left_attr]
}

///|
fn read_u16_le_matrix(bytes : BytesView, offset : Int) -> Int {
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  b0 | (b1 << 8)
}

///|
fn read_i16_le_matrix(bytes : BytesView, offset : Int) -> Int {
  let u = read_u16_le_matrix(bytes, offset)
  if u >= 0x8000 {
    u - 0x10000
  } else {
    u
  }
}

///|
/// Parse MeCab matrix.bin
pub fn parse_mecab_matrix(bytes : BytesView) -> (MecabMatrix?, String) {
  // Header: 4 bytes (lsize: u16, rsize: u16)
  if bytes.length() < 4 {
    return (None, "matrix.bin too small for header")
  }

  let lsize = read_u16_le_matrix(bytes, 0)
  let rsize = read_u16_le_matrix(bytes, 2)

  let expected_size = 4 + lsize * rsize * 2
  if bytes.length() < expected_size {
    return (None, "matrix.bin truncated (expected \{expected_size} bytes, got \{bytes.length()})")
  }

  // Parse cost matrix
  let count = lsize * rsize
  let costs : Array[Int] = Array::make(count, 0)
  for i = 0; i < count; i = i + 1 {
    costs[i] = read_i16_le_matrix(bytes, 4 + i * 2)
  }

  (Some({ lsize, rsize, costs }), "")
}

///|
/// Get connection cost between right context (previous word) and left context (current word)
pub fn MecabMatrix::cost(self : MecabMatrix, right_attr : Int, left_attr : Int) -> Int {
  if right_attr < 0 || right_attr >= self.rsize {
    return 10000  // default high cost
  }
  if left_attr < 0 || left_attr >= self.lsize {
    return 10000
  }
  let index = right_attr * self.lsize + left_attr
  if index >= 0 && index < self.costs.length() {
    self.costs[index]
  } else {
    10000
  }
}

///|
/// Get matrix dimensions
pub fn MecabMatrix::dimensions(self : MecabMatrix) -> (Int, Int) {
  (self.lsize, self.rsize)
}

///|
/// Get matrix statistics
pub fn MecabMatrix::stats(self : MecabMatrix) -> String {
  "MeCab Matrix: \{self.lsize} x \{self.rsize} = \{self.costs.length()} costs"
}
