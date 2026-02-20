///|
pub fn connection_num_ids_value() -> Int {
  connection_num_ids
}

///|
pub fn connection_id_to_compact_value(raw_id : Int) -> Int {
  if raw_id < 0 || raw_id >= connection_id_to_compact.length() {
    -1
  } else {
    connection_id_to_compact[raw_id]
  }
}

///|
pub fn connection_matrix_compact_value(
  right_compact : Int,
  left_compact : Int,
) -> Int {
  connection_matrix_compact[right_compact * connection_num_ids + left_compact]
}
