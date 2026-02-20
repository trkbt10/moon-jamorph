///|
fn contains_int(xs : Array[Int], value : Int) -> Bool {
  for x in xs {
    if x == value {
      return true
    }
  }
  false
}

///|
pub fn compact_ids_preserve_order(ids : Array[Int]) -> Array[Int] {
  let unique = Array::new()
  for id in ids {
    if !contains_int(unique, id) {
      unique.push(id)
    }
  }
  unique
}

///|
pub fn build_id_to_compact(unique_ids : Array[Int], max_id : Int) -> Array[Int] {
  let mapping = Array::makei(max_id + 1, _ => -1)
  for i in 0..<unique_ids.length() {
    let id = unique_ids[i]
    if id >= 0 && id <= max_id {
      mapping[id] = i
    }
  }
  mapping
}
