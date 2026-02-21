///|
fn build_utf16_offsets(chars : Array[Char]) -> Array[Int] {
  let offsets : Array[Int] = Array::makei(chars.length() + 1, _ => 0)
  let mut cu_pos = 0
  for i in 0..<chars.length() {
    let step = if chars[i].to_int() <= 0xFFFF { 1 } else { 2 }
    cu_pos = cu_pos + step
    offsets[i + 1] = cu_pos
  }
  offsets
}

///|
fn build_class_run_lengths(classes : Array[@types.CharClass]) -> Array[Int] {
  let n = classes.length()
  let run_lengths : Array[Int] = Array::makei(n, _ => 1)
  if n == 0 {
    return run_lengths
  }
  let mut i = n - 2
  while i >= 0 {
    run_lengths[i] = if classes[i] == classes[i + 1] {
      run_lengths[i + 1] + 1
    } else {
      1
    }
    i = i - 1
  }
  run_lengths
}

///|
fn intern_pos_detail(pool : Array[String], detail : String) -> Int {
  for i in 0..<pool.length() {
    if pool[i] == detail {
      return i
    }
  }
  pool.push(detail)
  pool.length() - 1
}

///|
pub fn decode_viterbi_with_classes(
  input : String,
  classes : Array[@types.CharClass],
) -> Array[@types.Morpheme] {
  let chars = input.to_array()
  let run_lengths = build_class_run_lengths(classes)
  decode_viterbi_with_precomputed(input, chars, classes, run_lengths)
}

///|
pub fn decode_viterbi_token_count_with_classes(
  input : String,
  classes : Array[@types.CharClass],
) -> Int {
  let chars = input.to_array()
  let run_lengths = build_class_run_lengths(classes)
  decode_viterbi_token_count_with_precomputed(chars, classes, run_lengths)
}

///|
pub fn decode_viterbi_token_count_with_precomputed(
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
) -> Int {
  let text_len = chars.length()
  if text_len == 0 {
    return 0
  }
  let run_lengths = if run_lengths.length() == text_len {
    run_lengths
  } else {
    build_class_run_lengths(classes)
  }
  let node_right_ids : Array[Int] = Array::new(capacity=text_len * 4)
  let node_best_costs : Array[Int] = Array::new(capacity=text_len * 4)
  let node_best_prevs : Array[Int] = Array::new(capacity=text_len * 4)
  let end_heads : Array[Int] = Array::makei(text_len + 1, _ => -1)
  let next_by_end : Array[Int] = Array::new(capacity=text_len * 4)
  let scratch_cands : Array[@types.TokenCandidate] = Array::new(capacity=16)
  let scratch_prev_indexes : Array[Int] = Array::new(capacity=16)
  let scratch_prev_best_costs : Array[Int] = Array::new(capacity=16)
  let scratch_prev_right_ids : Array[Int] = Array::new(capacity=16)
  let scratch_left_ids : Array[Int] = Array::new(capacity=8)
  let scratch_left_best_edges : Array[Int] = Array::new(capacity=8)
  let scratch_left_best_prevs : Array[Int] = Array::new(capacity=8)
  let mut eos_best_cost = @int.max_value
  let mut eos_best_prev = -1
  let bos_connection_id = @scorer.bos_connection_index()
  node_right_ids.push(bos_connection_id)
  node_best_costs.push(0)
  node_best_prevs.push(-1)
  next_by_end.push(-1)
  end_heads[0] = 0
  for pos in 0..<text_len {
    let head = end_heads[pos]
    if head < 0 {
      continue
    }
    scratch_prev_indexes.truncate(0)
    scratch_prev_best_costs.truncate(0)
    scratch_prev_right_ids.truncate(0)
    scratch_left_ids.truncate(0)
    scratch_left_best_edges.truncate(0)
    scratch_left_best_prevs.truncate(0)
    let mut cursor = head
    while cursor >= 0 {
      scratch_prev_indexes.push(cursor)
      scratch_prev_best_costs.push(node_best_costs[cursor])
      scratch_prev_right_ids.push(node_right_ids[cursor])
      cursor = next_by_end[cursor]
    }
    @lattice.candidates_at_into_with_run_lengths(
      scratch_cands, chars, classes, run_lengths, pos,
    )
    let cls = classes[pos]
    let run_len = run_lengths[pos]
    if scratch_prev_indexes.length() == 1 {
      let prev_best_cost = scratch_prev_best_costs[0]
      let prev_right_id = scratch_prev_right_ids[0]
      let prev_index = scratch_prev_indexes[0]
      for cand in scratch_cands {
        let token_len = cand.end_pos - cand.start_pos
        let emission_adj = @scorer.emission_adjustment(
          cand.pos,
          cls,
          token_len,
          run_len,
        )
        let best_cost = prev_best_cost +
          @scorer.connection_cost(prev_right_id, cand.left_id) +
          cand.word_cost +
          emission_adj
        let node_index = node_right_ids.length()
        node_right_ids.push(cand.right_id)
        node_best_costs.push(best_cost)
        node_best_prevs.push(prev_index)
        if cand.end_pos == text_len {
          next_by_end.push(-1)
          let eos_cost = best_cost +
            @scorer.connection_cost(cand.right_id, bos_connection_id)
          if eos_cost < eos_best_cost {
            eos_best_cost = eos_cost
            eos_best_prev = node_index
          }
        } else {
          next_by_end.push(end_heads[cand.end_pos])
          end_heads[cand.end_pos] = node_index
        }
      }
      continue
    }
    for cand in scratch_cands {
      let token_len = cand.end_pos - cand.start_pos
      let emission_adj = @scorer.emission_adjustment(
        cand.pos,
        cls,
        token_len,
        run_len,
      )
      let cand_word_cost = cand.word_cost
      let mut cache_idx = -1
      for j in 0..<scratch_left_ids.length() {
        if scratch_left_ids[j] == cand.left_id {
          cache_idx = j
          break
        }
      }
      let mut best_edge_cost = @int.max_value
      let mut best_prev = -1
      if cache_idx >= 0 {
        best_edge_cost = scratch_left_best_edges[cache_idx]
        best_prev = scratch_left_best_prevs[cache_idx]
      } else {
        for i in 0..<scratch_prev_indexes.length() {
          let edge_cost = scratch_prev_best_costs[i] +
            @scorer.connection_cost(scratch_prev_right_ids[i], cand.left_id)
          if edge_cost < best_edge_cost {
            best_edge_cost = edge_cost
            best_prev = scratch_prev_indexes[i]
          }
        }
        scratch_left_ids.push(cand.left_id)
        scratch_left_best_edges.push(best_edge_cost)
        scratch_left_best_prevs.push(best_prev)
      }
      if best_prev >= 0 {
        let best_cost = best_edge_cost + cand_word_cost + emission_adj
        let node_index = node_right_ids.length()
        node_right_ids.push(cand.right_id)
        node_best_costs.push(best_cost)
        node_best_prevs.push(best_prev)
        if cand.end_pos == text_len {
          next_by_end.push(-1)
          let eos_cost = best_cost +
            @scorer.connection_cost(cand.right_id, bos_connection_id)
          if eos_cost < eos_best_cost {
            eos_best_cost = eos_cost
            eos_best_prev = node_index
          }
        } else {
          next_by_end.push(end_heads[cand.end_pos])
          end_heads[cand.end_pos] = node_index
        }
      }
    }
  }
  if eos_best_prev < 0 {
    return 0
  }
  let mut path_len = 0
  let mut cursor = eos_best_prev
  while cursor > 0 {
    path_len = path_len + 1
    cursor = node_best_prevs[cursor]
  }
  path_len
}

///|
pub fn decode_viterbi_with_precomputed(
  input : String,
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
) -> Array[@types.Morpheme] {
  let text_len = chars.length()
  if text_len == 0 {
    return []
  }
  let run_lengths = if run_lengths.length() == text_len {
    run_lengths
  } else {
    build_class_run_lengths(classes)
  }
  let nodes : Array[@types.LatticeNode] = Array::new(capacity=text_len * 4)
  let end_heads : Array[Int] = Array::makei(text_len + 1, _ => -1)
  let next_by_end : Array[Int] = Array::new(capacity=text_len * 4)
  let scratch_cands : Array[@types.TokenCandidate] = Array::new(capacity=16)
  let scratch_prev_indexes : Array[Int] = Array::new(capacity=16)
  let scratch_prev_best_costs : Array[Int] = Array::new(capacity=16)
  let scratch_prev_right_ids : Array[Int] = Array::new(capacity=16)
  let scratch_left_ids : Array[Int] = Array::new(capacity=8)
  let scratch_left_best_edges : Array[Int] = Array::new(capacity=8)
  let scratch_left_best_prevs : Array[Int] = Array::new(capacity=8)
  let pos_detail_pool : Array[String] = Array::new(capacity=64)
  let mecab_feature_pool : Array[String] = Array::new(capacity=64)
  let mut eos_best_cost = @int.max_value
  let mut eos_best_prev = -1
  let bos_connection_id = @scorer.bos_connection_index()
  let bos_pos_detail_id = intern_pos_detail(pos_detail_pool, "BOS/EOS,*,*,*")
  let bos_mecab_feature_id = intern_pos_detail(
    mecab_feature_pool, "BOS/EOS,*,*,*,*,*,*,*,*",
  )
  nodes.push({
    start_pos: 0,
    end_pos: 0,
    pos: @types.POS::BosEos,
    pos_detail_id: bos_pos_detail_id,
    mecab_feature_id: bos_mecab_feature_id,
    right_id: bos_connection_id,
    best_cost: 0,
    best_prev: -1,
  })
  next_by_end.push(-1)
  end_heads[0] = 0
  for pos in 0..<text_len {
    let head = end_heads[pos]
    if head < 0 {
      continue
    }
    scratch_prev_indexes.truncate(0)
    scratch_prev_best_costs.truncate(0)
    scratch_prev_right_ids.truncate(0)
    scratch_left_ids.truncate(0)
    scratch_left_best_edges.truncate(0)
    scratch_left_best_prevs.truncate(0)
    let mut cursor = head
    while cursor >= 0 {
      let prev = nodes[cursor]
      scratch_prev_indexes.push(cursor)
      scratch_prev_best_costs.push(prev.best_cost)
      scratch_prev_right_ids.push(prev.right_id)
      cursor = next_by_end[cursor]
    }
    @lattice.candidates_at_into_with_run_lengths(
      scratch_cands, chars, classes, run_lengths, pos,
    )
    let cls = classes[pos]
    let run_len = run_lengths[pos]
    if scratch_prev_indexes.length() == 1 {
      let prev_best_cost = scratch_prev_best_costs[0]
      let prev_right_id = scratch_prev_right_ids[0]
      let prev_index = scratch_prev_indexes[0]
      let mut cached_detail = ""
      let mut cached_detail_id = -1
      let mut cached_feature = ""
      let mut cached_feature_id = -1
      for cand in scratch_cands {
        let token_len = cand.end_pos - cand.start_pos
        let emission_adj = @scorer.emission_adjustment(
          cand.pos,
          cls,
          token_len,
          run_len,
        )
        let pos_detail_id = if cached_detail_id >= 0 &&
          cached_detail == cand.pos_detail {
          cached_detail_id
        } else {
          let id = intern_pos_detail(pos_detail_pool, cand.pos_detail)
          cached_detail = cand.pos_detail
          cached_detail_id = id
          id
        }
        let mecab_feature_id = if cached_feature_id >= 0 &&
          cached_feature == cand.mecab_feature {
          cached_feature_id
        } else {
          let id = intern_pos_detail(mecab_feature_pool, cand.mecab_feature)
          cached_feature = cand.mecab_feature
          cached_feature_id = id
          id
        }
        let best_cost = prev_best_cost +
          @scorer.connection_cost(prev_right_id, cand.left_id) +
          cand.word_cost +
          emission_adj
        let node_index = nodes.length()
        nodes.push({
          start_pos: cand.start_pos,
          end_pos: cand.end_pos,
          pos: cand.pos,
          pos_detail_id,
          mecab_feature_id,
          right_id: cand.right_id,
          best_cost,
          best_prev: prev_index,
        })
        if cand.end_pos == text_len {
          next_by_end.push(-1)
          let eos_cost = best_cost +
            @scorer.connection_cost(cand.right_id, bos_connection_id)
          if eos_cost < eos_best_cost {
            eos_best_cost = eos_cost
            eos_best_prev = node_index
          }
        } else {
          next_by_end.push(end_heads[cand.end_pos])
          end_heads[cand.end_pos] = node_index
        }
      }
      continue
    }
    let mut cached_detail = ""
    let mut cached_detail_id = -1
    let mut cached_feature = ""
    let mut cached_feature_id = -1
    for cand in scratch_cands {
      let token_len = cand.end_pos - cand.start_pos
      let emission_adj = @scorer.emission_adjustment(
        cand.pos,
        cls,
        token_len,
        run_len,
      )
      let cand_word_cost = cand.word_cost
      let pos_detail_id = if cached_detail_id >= 0 &&
        cached_detail == cand.pos_detail {
        cached_detail_id
      } else {
        let id = intern_pos_detail(pos_detail_pool, cand.pos_detail)
        cached_detail = cand.pos_detail
        cached_detail_id = id
        id
      }
      let mecab_feature_id = if cached_feature_id >= 0 &&
        cached_feature == cand.mecab_feature {
        cached_feature_id
      } else {
        let id = intern_pos_detail(mecab_feature_pool, cand.mecab_feature)
        cached_feature = cand.mecab_feature
        cached_feature_id = id
        id
      }
      let mut cache_idx = -1
      for j in 0..<scratch_left_ids.length() {
        if scratch_left_ids[j] == cand.left_id {
          cache_idx = j
          break
        }
      }
      let mut best_edge_cost = @int.max_value
      let mut best_prev = -1
      if cache_idx >= 0 {
        best_edge_cost = scratch_left_best_edges[cache_idx]
        best_prev = scratch_left_best_prevs[cache_idx]
      } else {
        for i in 0..<scratch_prev_indexes.length() {
          let edge_cost = scratch_prev_best_costs[i] +
            @scorer.connection_cost(scratch_prev_right_ids[i], cand.left_id)
          if edge_cost < best_edge_cost {
            best_edge_cost = edge_cost
            best_prev = scratch_prev_indexes[i]
          }
        }
        scratch_left_ids.push(cand.left_id)
        scratch_left_best_edges.push(best_edge_cost)
        scratch_left_best_prevs.push(best_prev)
      }
      if best_prev >= 0 {
        let best_cost = best_edge_cost + cand_word_cost + emission_adj
        let node_index = nodes.length()
        nodes.push({
          start_pos: cand.start_pos,
          end_pos: cand.end_pos,
          pos: cand.pos,
          pos_detail_id,
          mecab_feature_id,
          right_id: cand.right_id,
          best_cost,
          best_prev,
        })
        if cand.end_pos == text_len {
          next_by_end.push(-1)
          let eos_cost = best_cost +
            @scorer.connection_cost(cand.right_id, bos_connection_id)
          if eos_cost < eos_best_cost {
            eos_best_cost = eos_cost
            eos_best_prev = node_index
          }
        } else {
          next_by_end.push(end_heads[cand.end_pos])
          end_heads[cand.end_pos] = node_index
        }
      }
    }
  }
  if eos_best_prev < 0 {
    return []
  }
  let utf16_offsets = if input.length() == text_len {
    []
  } else {
    build_utf16_offsets(chars)
  }
  let mut path_len = 0
  let mut len_cursor = eos_best_prev
  while len_cursor > 0 {
    path_len = path_len + 1
    len_cursor = nodes[len_cursor].best_prev
  }
  let path : Array[@types.Morpheme] = Array::makei(path_len, _ => {
    surface: "",
    pos: @types.POS::Unknown,
    pos_detail: "",
    mecab_feature: "",
    start_pos: 0,
    end_pos: 0,
  })
  let mut cursor = eos_best_prev
  let mut write_index = path_len - 1
  while cursor > 0 {
    let node = nodes[cursor]
    let surface = if utf16_offsets.is_empty() {
      input.unsafe_substring(start=node.start_pos, end=node.end_pos)
    } else {
      input.unsafe_substring(
        start=utf16_offsets[node.start_pos],
        end=utf16_offsets[node.end_pos],
      )
    }
    path[write_index] = {
      surface,
      pos: node.pos,
      pos_detail: pos_detail_pool[node.pos_detail_id],
      mecab_feature: mecab_feature_pool[node.mecab_feature_id],
      start_pos: node.start_pos,
      end_pos: node.end_pos,
    }
    cursor = node.best_prev
    write_index = write_index - 1
  }
  path
}
