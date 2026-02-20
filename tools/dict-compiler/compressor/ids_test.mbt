///|
test "compressor should build compact id map" {
  let ids = [2, 10, 2, 5]
  let unique = compact_ids_preserve_order(ids)
  inspect(unique, content="[2, 10, 5]")
  let map = build_id_to_compact(unique, 10)
  inspect(map[2], content="0")
  inspect(map[10], content="1")
  inspect(map[5], content="2")
}
