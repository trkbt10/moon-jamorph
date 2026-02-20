///|
test "builder should count distinct first chars" {
  let surfaces = ["東京", "大学", "東京駅", "すもも"]
  inspect(first_char_count(surfaces), content="3")
}
