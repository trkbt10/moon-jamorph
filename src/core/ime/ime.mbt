///|
/// Extract first POS tag from feature string
fn extract_pos1(feature : String) -> String {
  let mut end = 0
  for i, ch in feature {
    if ch == ',' {
      end = i
      break
    }
  }
  if end > 0 {
    feature[:end].to_string() catch { _ => feature }
  } else {
    feature
  }
}

///|
/// Extract POS detail (first 4 fields) from feature string
fn extract_pos_detail(feature : String) -> String {
  let mut comma_count = 0
  let mut end = 0
  for i, ch in feature {
    if ch == ',' {
      comma_count += 1
      if comma_count == 4 {
        end = i
        break
      }
    }
  }
  if end > 0 {
    feature[:end].to_string() catch { _ => feature }
  } else {
    feature
  }
}

///|
/// Lookup dictionary entries by hiragana reading
/// Returns candidates sorted by word cost (lower is better)
pub fn lookup_by_reading(reading : String) -> Array[@types.ReadingCandidate] {
  if !@runtime.is_ready() || reading.length() == 0 {
    return []
  }
  let entry_indices = @runtime.get_entries_by_reading(reading)
  let candidates : Array[@types.ReadingCandidate] = Array::new(
    capacity=entry_indices.length(),
  )
  for idx in entry_indices {
    match @runtime.get_entry(idx) {
      Some(entry) => {
        let reading_str = @runtime.extract_reading_from_feature(
          entry.mecab_feature,
        )
        let hiragana = @runtime.katakana_to_hiragana(reading_str)
        candidates.push({
          surface: entry.surface,
          reading: hiragana,
          pos: extract_pos1(entry.mecab_feature),
          pos_detail: extract_pos_detail(entry.mecab_feature),
          cost: entry.word_cost,
          connection_id: entry.right_id,
        })
      }
      None => ()
    }
  }
  candidates.sort_by(fn(a, b) { a.cost - b.cost })
  candidates
}

///|
/// Prefix search for incremental IME input
/// Given partial hiragana reading, returns all matching candidates
pub fn prefix_search(prefix : String) -> Array[@types.ReadingCandidate] {
  if !@runtime.is_ready() || prefix.length() == 0 {
    return []
  }
  let all_readings = @runtime.get_all_readings()
  let candidates : Array[@types.ReadingCandidate] = []
  for reading in all_readings {
    if reading.has_prefix(prefix) {
      let entry_indices = @runtime.get_entries_by_reading(reading)
      for idx in entry_indices {
        match @runtime.get_entry(idx) {
          Some(entry) => {
            let reading_str = @runtime.extract_reading_from_feature(
              entry.mecab_feature,
            )
            let hiragana = @runtime.katakana_to_hiragana(reading_str)
            candidates.push({
              surface: entry.surface,
              reading: hiragana,
              pos: extract_pos1(entry.mecab_feature),
              pos_detail: extract_pos_detail(entry.mecab_feature),
              cost: entry.word_cost,
              connection_id: entry.right_id,
            })
          }
          None => ()
        }
      }
    }
  }
  candidates.sort_by(fn(a, b) { a.cost - b.cost })
  candidates
}

///|
/// Analyze preceding context for ML reranking
/// Tokenizes the input text and returns context morphemes
pub fn analyze_context(text : String) -> Array[@types.ContextMorpheme] {
  if !@runtime.is_ready() || text.length() == 0 {
    return []
  }
  let morphemes = @tokenizer.Tokenizer::new().tokenize(text)
  let context : Array[@types.ContextMorpheme] = Array::new(
    capacity=morphemes.length(),
  )
  for m in morphemes {
    let reading_str = @runtime.extract_reading_from_feature(m.mecab_feature)
    let hiragana = @runtime.katakana_to_hiragana(reading_str)
    context.push({
      surface: m.surface,
      reading: hiragana,
      pos: extract_pos1(m.mecab_feature),
      connection_id: 0,
    })
  }
  context
}

///|
/// Get all dictionary entries for custom indexing
pub fn get_all_entries() -> Array[@types.RuntimeEntry] {
  @runtime.get_all_entries()
}

///|
/// Get connection cost between two morphemes
pub fn connection_cost(left_id : Int, right_id : Int) -> Int {
  @runtime.connection_cost(right_id, left_id)
}
