///|
let unknown_connection_penalty = 10000

///|
let legacy_connection_matrix_4x4 : ReadOnlyArray[Int] = [
  0, 0, 3000, 2000, 3000, 800, 100, 1500, 3000, 100, 2000, 1500, 2000, 1200, 1200,
  1000,
]

///|
fn to_compact_id(raw_id : Int) -> Int {
  @standard.connection_id_to_compact_value(raw_id)
}

///|
pub fn connection_cost(right_id : Int, left_id : Int) -> Int {
  if right_id >= 0 && right_id < 4 && left_id >= 0 && left_id < 4 {
    return legacy_connection_matrix_4x4[right_id * 4 + left_id]
  }
  let right_compact = to_compact_id(right_id)
  let left_compact = to_compact_id(left_id)
  if right_compact < 0 || left_compact < 0 {
    return unknown_connection_penalty
  }
  @standard.connection_matrix_compact_value(right_compact, left_compact)
}
