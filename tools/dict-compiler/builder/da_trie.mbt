///|
pub struct DATrieBuildResult {
  char_table : Array[Char]
  base : Array[Int]
  check : Array[Int]
  term_starts : Array[Int]
  term_entry_indexes : Array[Int]
}

///|
fn index_of_char(table : Array[Char], ch : Char) -> Int {
  for i in 0..<table.length() {
    if table[i] == ch {
      return i
    }
  }
  -1
}

///|
fn code_for_char(table : Array[Char], ch : Char) -> Int {
  let idx = index_of_char(table, ch)
  if idx < 0 {
    0
  } else {
    idx + 1
  }
}

///|
fn code_for_char_mut(table : Array[Char], ch : Char) -> Int {
  let idx = index_of_char(table, ch)
  if idx >= 0 {
    return idx + 1
  }
  table.push(ch)
  table.length()
}

///|
fn ensure_int_capacity(xs : Array[Int], index : Int, fill : Int) -> Unit {
  while xs.length() <= index {
    xs.push(fill)
  }
}

///|
fn find_child_index(child_keys : Array[Int], code : Int) -> Int {
  for i in 0..<child_keys.length() {
    if child_keys[i] == code {
      return i
    }
  }
  -1
}

///|
fn find_base_for_codes(
  check : Array[Int],
  used_root_index : Int,
  child_codes : Array[Int],
) -> Int {
  if child_codes.is_empty() {
    return 0
  }
  let mut base = 1
  while true {
    let mut ok = true
    for code in child_codes {
      let slot = base + code
      if slot == used_root_index {
        ok = false
      } else {
        ensure_int_capacity(check, slot, -1)
        if check[slot] != -1 {
          ok = false
        }
      }
      if !ok {
        break
      }
    }
    if ok {
      return base
    }
    base = base + 1
  }
  0
}

///|
pub fn build_da_trie_from_surfaces(
  surfaces : Array[String],
) -> DATrieBuildResult {
  let char_table : Array[Char] = Array::new()

  // mutable trie (temporary)
  let node_child_keys : Array[Array[Int]] = [Array::new()]
  let node_child_nodes : Array[Array[Int]] = [Array::new()]
  let node_term_start : Array[Int] = [-1]
  let node_term_end : Array[Int] = [-1]
  for entry_index in 0..<surfaces.length() {
    let chars = surfaces[entry_index].to_array()
    let mut node = 0
    for ch in chars {
      let code = code_for_char_mut(char_table, ch)
      let keys = node_child_keys[node]
      let nexts = node_child_nodes[node]
      let child_pos = find_child_index(keys, code)
      if child_pos >= 0 {
        node = nexts[child_pos]
      } else {
        let new_node = node_child_keys.length()
        keys.push(code)
        nexts.push(new_node)
        node_child_keys.push(Array::new())
        node_child_nodes.push(Array::new())
        node_term_start.push(-1)
        node_term_end.push(-1)
        node = new_node
      }
    }
    if node_term_start[node] < 0 {
      node_term_start[node] = entry_index
    }
    node_term_end[node] = entry_index + 1
  }

  // double-array allocation
  let base : Array[Int] = [-1, 0]
  let check : Array[Int] = [-1, 0]
  let trie_to_da : Array[Int] = Array::makei(node_child_keys.length(), _ => -1)
  trie_to_da[0] = 1
  let queue : Array[Int] = [0]
  let mut qpos = 0
  while qpos < queue.length() {
    let trie_node = queue[qpos]
    qpos = qpos + 1
    let da_node = trie_to_da[trie_node]
    let keys = node_child_keys[trie_node]
    if keys.is_empty() {
      ensure_int_capacity(base, da_node, -1)
      base[da_node] = 0
      continue
    }
    let b = find_base_for_codes(check, 1, keys)
    ensure_int_capacity(base, da_node, -1)
    base[da_node] = b
    let nexts = node_child_nodes[trie_node]
    for i in 0..<keys.length() {
      let code = keys[i]
      let child_trie_node = nexts[i]
      let slot = b + code
      ensure_int_capacity(base, slot, -1)
      ensure_int_capacity(check, slot, -1)
      check[slot] = da_node
      trie_to_da[child_trie_node] = slot
      queue.push(child_trie_node)
    }
  }
  let max_da_node = check.length() - 1
  let term_counts : Array[Int] = Array::makei(max_da_node + 1, _ => 0)
  for trie_node in 0..<trie_to_da.length() {
    let da_node = trie_to_da[trie_node]
    if da_node < 0 {
      continue
    }
    let start = node_term_start[trie_node]
    let end = node_term_end[trie_node]
    if start >= 0 && end >= start {
      term_counts[da_node] = end - start
    }
  }
  let term_starts : Array[Int] = Array::makei(max_da_node + 2, _ => 0)
  for i in 0..<=max_da_node {
    term_starts[i + 1] = term_starts[i] + term_counts[i]
  }
  let term_entry_indexes : Array[Int] = Array::makei(
    term_starts[max_da_node + 1],
    _ => -1,
  )
  let fill_cursor : Array[Int] = Array::makei(max_da_node + 1, i => term_starts[i])
  for trie_node in 0..<trie_to_da.length() {
    let da_node = trie_to_da[trie_node]
    if da_node < 0 {
      continue
    }
    let start = node_term_start[trie_node]
    let end = node_term_end[trie_node]
    if start >= 0 && end >= start {
      let mut p = fill_cursor[da_node]
      for entry_index in start..<end {
        term_entry_indexes[p] = entry_index
        p = p + 1
      }
      fill_cursor[da_node] = p
    }
  }
  { char_table, base, check, term_starts, term_entry_indexes }
}

///|
pub fn common_prefix_entry_indexes(
  trie : DATrieBuildResult,
  chars : Array[Char],
  start : Int,
) -> Array[Int] {
  let results : Array[Int] = Array::new()
  if trie.base.length() <= 1 || start >= chars.length() {
    return results
  }
  let mut node = 1
  for i in start..<chars.length() {
    let code = code_for_char(trie.char_table, chars[i])
    if code == 0 {
      break
    }
    let next = trie.base[node] + code
    if next < 0 || next >= trie.check.length() || trie.check[next] != node {
      break
    }
    node = next
    let from = trie.term_starts[node]
    let to = trie.term_starts[node + 1]
    for j in from..<to {
      results.push(trie.term_entry_indexes[j])
    }
  }
  results
}
