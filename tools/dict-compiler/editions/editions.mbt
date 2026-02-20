///|
pub const EDITION_NANO = "nano"

///|
pub const EDITION_MINI = "mini"

///|
pub const EDITION_STANDARD = "standard"

///|
pub const EDITION_FULL = "full"

///|
pub fn normalize_edition_name(name : String) -> String {
  name.to_lower()
}

///|
fn canonical_pos_tag(pos_tag : String) -> String {
  match pos_tag {
    "NOUN_GENERAL" | "名詞,一般" => "NOUN_GENERAL"
    "NOUN_PROPER" | "名詞,固有名詞" => "NOUN_PROPER"
    "NOUN_NON_INDEPENDENT" | "名詞,非自立" => "NOUN_NON_INDEPENDENT"
    "PARTICLE" | "助詞" => "PARTICLE"
    _ => "UNKNOWN"
  }
}

///|
pub fn is_supported_pos_tag(pos_tag : String) -> Bool {
  canonical_pos_tag(pos_tag) != "UNKNOWN"
}

///|
pub fn should_include_pos_tag(pos_tag : String, edition : String) -> Bool {
  let pos = canonical_pos_tag(pos_tag)
  let edition = normalize_edition_name(edition)
  match edition {
    "nano" => pos == "NOUN_GENERAL" || pos == "PARTICLE"
    "mini" => pos == "NOUN_GENERAL" || pos == "PARTICLE" || pos == "NOUN_PROPER"
    "standard" | "full" => pos != "UNKNOWN"
    _ => false
  }
}
