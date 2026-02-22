///|
/// Load MeCab dictionary and convert to runtime format
///
/// This module bridges MeCab sys.dic/matrix.bin to micado's runtime dictionary.

///|
/// Loaded MeCab dictionary bundle
pub struct MecabDicBundle {
  sys_dic : MecabDictionary
  matrix : MecabMatrix
  charset : String
}

///|
/// Load and parse MeCab dictionary files from bytes
pub fn load_mecab_dic_from_bytes(
  sys_dic_bytes : BytesView,
  matrix_bytes : BytesView,
) -> (MecabDicBundle?, String) {
  // Parse sys.dic
  let (sys_dic_opt, sys_err) = parse_mecab_sys_dic(sys_dic_bytes)
  let sys_dic = match sys_dic_opt {
    Some(d) => d
    None => return (None, "sys.dic: \{sys_err}")
  }

  // Parse matrix.bin
  let (matrix_opt, matrix_err) = parse_mecab_matrix(matrix_bytes)
  let matrix = match matrix_opt {
    Some(m) => m
    None => return (None, "matrix.bin: \{matrix_err}")
  }

  let charset = sys_dic.header.charset
  (Some({ sys_dic, matrix, charset }), "")
}

///|
/// Convert MeCab feature string to POS class
fn feature_to_pos(feature : String) -> @types.POS {
  // MeCab feature format: pos1,pos2,pos3,pos4,conj1,conj2,base,read,pron
  // e.g., "名詞,一般,*,*,*,*,猫,ネコ,ネコ"
  if feature.has_prefix("名詞,固有名詞") {
    return @types.POS::NounProper
  }
  if feature.has_prefix("名詞,非自立") {
    return @types.POS::NounNonIndependent
  }
  if feature.has_prefix("名詞") {
    return @types.POS::NounGeneral
  }
  if feature.has_prefix("助詞") {
    return @types.POS::Particle
  }
  if feature.has_prefix("BOS/EOS") {
    return @types.POS::BosEos
  }
  @types.POS::Unknown
}

///|
/// Extract POS detail from feature string (first 4 fields)
fn feature_to_pos_detail(feature : String) -> String {
  let cols = feature.split(",").map(StringView::to_string).collect()
  if cols.length() >= 4 {
    let c0 = if cols[0].length() > 0 { cols[0] } else { "*" }
    let c1 = if cols[1].length() > 0 { cols[1] } else { "*" }
    let c2 = if cols[2].length() > 0 { cols[2] } else { "*" }
    let c3 = if cols[3].length() > 0 { cols[3] } else { "*" }
    "\{c0},\{c1},\{c2},\{c3}"
  } else {
    feature
  }
}

///|
/// Build runtime dictionary entries from MeCab dictionary
/// This performs Double-Array traversal to extract all entries
pub fn MecabDicBundle::build_entries(self : MecabDicBundle) -> Array[@types.DictEntry] {
  let entries : Array[@types.DictEntry] = []
  let dic = self.sys_dic

  // We need to traverse the Double-Array to find all surfaces
  // MeCab's DA structure: traverse all valid paths to collect entries

  // For efficiency, we'll iterate through tokens directly
  // and reconstruct surfaces from the DA paths
  // This is complex, so we'll use a simpler approach:
  // iterate through all possible DA nodes and check for terminals

  let da_size = dic.da_base.length()
  let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()

  // BFS/DFS through the DA to find all terminal nodes
  fn traverse(
    dic : MecabDictionary,
    node : Int,
    path : @buffer.Buffer,
    entries : Array[@types.DictEntry],
    visited : @hashmap.HashMap[Int, Bool],
  ) {
    if node < 0 || node >= dic.da_base.length() {
      return
    }
    if visited.get(node) is Some(true) {
      return
    }
    visited.set(node, true)

    let base = dic.da_base[node]

    // Check if this node has a terminal (negative base or special marker)
    // In MeCab, base < 0 indicates token data
    // Actually, MeCab uses a different encoding...
    // Let me check: base points to token array when we reach end of word

    // For each possible next character (0-255)
    for c = 1; c < 256; c = c + 1 {
      let next = base + c
      if next >= 0 && next < dic.da_check.length() {
        if dic.da_check[next] == node {
          // Valid transition
          path.write_byte(c.to_byte())
          traverse(dic, next, path, entries, visited)
          // Backtrack - remove last byte
          let bytes = path.to_bytes()
          path.reset()
          for i = 0; i < bytes.length() - 1; i = i + 1 {
            path.write_byte(bytes[i])
          }
        }
      }
    }

    // Check for end-of-string (character 0)
    let term_next = base
    if term_next >= 0 && term_next < dic.da_check.length() {
      if dic.da_check[term_next] == node {
        // This is a terminal node - extract token info
        // The base at term_next encodes token array position
        let token_base = dic.da_base[term_next]
        if token_base < 0 {
          // Decode token index (MeCab encoding)
          let token_idx = (-token_base) - 1
          if token_idx >= 0 && token_idx < dic.tokens.length() {
            let surface = @utf8.decode_lossy(path.to_bytes()[:])
            let token = dic.tokens[token_idx]
            let feature = dic.get_feature(token_idx)
            entries.push({
              surface,
              pos: feature_to_pos(feature),
              pos_detail: feature_to_pos_detail(feature),
              mecab_feature: feature,
              left_id: token.left_attr,
              right_id: token.right_attr,
              word_cost: token.wcost,
            })
          }
        }
      }
    }
  }

  // Start traversal from root (node 0)
  let path = @buffer.new(size_hint=64)
  traverse(dic, 0, path, entries, visited)

  entries
}

///|
/// Get bundle statistics
pub fn MecabDicBundle::stats(self : MecabDicBundle) -> String {
  let dic_stats = self.sys_dic.stats()
  let matrix_stats = self.matrix.stats()
  "\{dic_stats}\n\{matrix_stats}"
}
