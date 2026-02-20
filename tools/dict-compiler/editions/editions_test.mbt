///|
test "editions should filter pos tags" {
  inspect(should_include_pos_tag("NOUN_GENERAL", "nano"), content="true")
  inspect(should_include_pos_tag("NOUN_PROPER", "nano"), content="false")
  inspect(should_include_pos_tag("NOUN_PROPER", "mini"), content="true")
  inspect(should_include_pos_tag("PARTICLE", "standard"), content="true")
}
