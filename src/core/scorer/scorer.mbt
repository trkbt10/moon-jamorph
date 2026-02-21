///|
let unknown_connection_penalty = 10000

///|
let legacy_connection_matrix_4x4 : ReadOnlyArray[Int] = [
  0, 0, 3000, 2000, 3000, 800, 100, 1500, 3000, 100, 2000, 1500, 2000, 1200, 1200,
  1000,
]

///|
pub fn compact_connection_id(raw_id : Int) -> Int {
  if raw_id >= 0 && raw_id < 4 {
    raw_id
  } else {
    -1
  }
}

///|
pub fn connection_cost_with_compact(
  right_id : Int,
  left_id : Int,
  right_compact_id : Int,
  left_compact_id : Int,
) -> Int {
  let _ = right_compact_id
  let _ = left_compact_id
  if right_id >= 0 && right_id < 4 && left_id >= 0 && left_id < 4 {
    return legacy_connection_matrix_4x4[right_id * 4 + left_id]
  }
  unknown_connection_penalty
}

///|
pub fn connection_cost(right_id : Int, left_id : Int) -> Int {
  connection_cost_with_compact(
    right_id,
    left_id,
    compact_connection_id(right_id),
    compact_connection_id(left_id),
  )
}
