///|
priv struct PreparedConstraint {
  valid : Bool
  allow_unknown : Bool
  must_break_positions : Array[Int]
  forbid_break_positions : Array[Int]
  must_cover_spans : Array[@types.SpanConstraint]
  allowed_pos : Array[@types.POS]
  disallowed_pos : Array[@types.POS]
  required_all_mask : Int
}

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
fn contains_pos(xs : Array[@types.POS], value : @types.POS) -> Bool {
  for x in xs {
    if x == value {
      return true
    }
  }
  false
}

///|
fn add_unique_int(xs : Array[Int], value : Int) -> Unit {
  if !contains_int(xs, value) {
    xs.push(value)
  }
}

///|
fn contains_span(
  xs : Array[@types.SpanConstraint],
  start_pos : Int,
  end_pos : Int,
) -> Bool {
  for span in xs {
    if span.start_pos == start_pos && span.end_pos == end_pos {
      return true
    }
  }
  false
}

///|
fn add_unique_span(
  xs : Array[@types.SpanConstraint],
  start_pos : Int,
  end_pos : Int,
) -> Unit {
  if !contains_span(xs, start_pos, end_pos) {
    xs.push({ start_pos, end_pos })
  }
}

///|
fn invalid_prepared_constraint() -> PreparedConstraint {
  {
    valid: false,
    allow_unknown: true,
    must_break_positions: [],
    forbid_break_positions: [],
    must_cover_spans: [],
    allowed_pos: [],
    disallowed_pos: [],
    required_all_mask: 0,
  }
}

///|
fn prepare_constraint(
  constraint : @types.ParseConstraint,
  text_len : Int,
) -> PreparedConstraint {
  let must_break_positions : Array[Int] = Array::new(capacity=8)
  let forbid_break_positions : Array[Int] = Array::new(capacity=8)
  let must_cover_spans : Array[@types.SpanConstraint] = Array::new(capacity=8)
  for pos in constraint.must_break_positions {
    if pos < 0 || pos > text_len {
      return invalid_prepared_constraint()
    }
    if pos > 0 && pos < text_len {
      add_unique_int(must_break_positions, pos)
    }
  }
  for pos in constraint.forbid_break_positions {
    if pos < 0 || pos > text_len {
      return invalid_prepared_constraint()
    }
    if pos == 0 {
      continue
    }
    if pos == text_len {
      return invalid_prepared_constraint()
    }
    add_unique_int(forbid_break_positions, pos)
  }
  for pos in must_break_positions {
    if contains_int(forbid_break_positions, pos) {
      return invalid_prepared_constraint()
    }
  }
  for span in constraint.must_cover_spans {
    if span.start_pos < 0 ||
      span.end_pos < 0 ||
      span.start_pos >= span.end_pos ||
      span.end_pos > text_len {
      return invalid_prepared_constraint()
    }
    add_unique_span(must_cover_spans, span.start_pos, span.end_pos)
  }
  let required_count = must_break_positions.length() + must_cover_spans.length()
  if required_count > 30 {
    return invalid_prepared_constraint()
  }
  let required_all_mask = if required_count == 0 {
    0
  } else {
    (1 << required_count) - 1
  }
  {
    valid: true,
    allow_unknown: constraint.allow_unknown,
    must_break_positions,
    forbid_break_positions,
    must_cover_spans,
    allowed_pos: constraint.allowed_pos,
    disallowed_pos: constraint.disallowed_pos,
    required_all_mask,
  }
}

///|
fn is_candidate_allowed(
  constraint : PreparedConstraint,
  cand : @types.TokenCandidate,
) -> Bool {
  if contains_int(constraint.forbid_break_positions, cand.end_pos) {
    return false
  }
  if !constraint.allow_unknown && cand.pos == @types.POS::Unknown {
    return false
  }
  if contains_pos(constraint.disallowed_pos, cand.pos) {
    return false
  }
  if !constraint.allowed_pos.is_empty() &&
    !contains_pos(constraint.allowed_pos, cand.pos) {
    return false
  }
  true
}

///|
fn candidate_required_mask_delta(
  constraint : PreparedConstraint,
  start_pos : Int,
  end_pos : Int,
) -> Int {
  let mut delta = 0
  for i in 0..<constraint.must_break_positions.length() {
    if constraint.must_break_positions[i] == end_pos {
      delta = delta | (1 << i)
      break
    }
  }
  let offset = constraint.must_break_positions.length()
  for i in 0..<constraint.must_cover_spans.length() {
    let span = constraint.must_cover_spans[i]
    if span.start_pos == start_pos && span.end_pos == end_pos {
      delta = delta | (1 << (offset + i))
    }
  }
  delta
}

///|
fn is_unconstrained(constraint : @types.ParseConstraint) -> Bool {
  constraint.allow_unknown &&
  constraint.must_break_positions.is_empty() &&
  constraint.forbid_break_positions.is_empty() &&
  constraint.must_cover_spans.is_empty() &&
  constraint.allowed_pos.is_empty() &&
  constraint.disallowed_pos.is_empty()
}

///|
fn remove_entry_swap(
  masks : Array[Int],
  costs : Array[Int],
  prev_nodes : Array[Int],
  prev_path_indexes : Array[Int],
  remove_index : Int,
) -> Unit {
  let new_len = masks.length() - 1
  if remove_index != new_len {
    masks[remove_index] = masks[new_len]
    costs[remove_index] = costs[new_len]
    prev_nodes[remove_index] = prev_nodes[new_len]
    prev_path_indexes[remove_index] = prev_path_indexes[new_len]
  }
  masks.truncate(new_len)
  costs.truncate(new_len)
  prev_nodes.truncate(new_len)
  prev_path_indexes.truncate(new_len)
}

///|
fn insert_path_with_mask_limit(
  masks : Array[Int],
  costs : Array[Int],
  prev_nodes : Array[Int],
  prev_path_indexes : Array[Int],
  mask : Int,
  cost : Int,
  prev_node : Int,
  prev_path_index : Int,
  limit : Int,
) -> Unit {
  masks.push(mask)
  costs.push(cost)
  prev_nodes.push(prev_node)
  prev_path_indexes.push(prev_path_index)
  let mut same_count = 0
  let mut worst_index = -1
  let mut worst_cost = 0
  for i in 0..<masks.length() {
    if masks[i] != mask {
      continue
    }
    same_count = same_count + 1
    if worst_index < 0 || costs[i] > worst_cost {
      worst_index = i
      worst_cost = costs[i]
    }
  }
  if same_count > limit && worst_index >= 0 {
    remove_entry_swap(masks, costs, prev_nodes, prev_path_indexes, worst_index)
  }
}

///|
fn insert_final_with_limit(
  node_indexes : Array[Int],
  path_indexes : Array[Int],
  total_costs : Array[Int],
  node_index : Int,
  path_index : Int,
  total_cost : Int,
  limit : Int,
) -> Unit {
  node_indexes.push(node_index)
  path_indexes.push(path_index)
  total_costs.push(total_cost)
  if node_indexes.length() <= limit {
    return
  }
  let mut worst_index = 0
  for i in 1..<total_costs.length() {
    if total_costs[i] > total_costs[worst_index] {
      worst_index = i
    }
  }
  let new_len = node_indexes.length() - 1
  if worst_index != new_len {
    node_indexes[worst_index] = node_indexes[new_len]
    path_indexes[worst_index] = path_indexes[new_len]
    total_costs[worst_index] = total_costs[new_len]
  }
  node_indexes.truncate(new_len)
  path_indexes.truncate(new_len)
  total_costs.truncate(new_len)
}

///|
fn sort_final_by_cost(
  node_indexes : Array[Int],
  path_indexes : Array[Int],
  total_costs : Array[Int],
) -> Unit {
  for i in 0..<total_costs.length() {
    let mut min_index = i
    for j in (i + 1)..<total_costs.length() {
      if total_costs[j] < total_costs[min_index] {
        min_index = j
      }
    }
    if min_index != i {
      let tmp_cost = total_costs[i]
      total_costs[i] = total_costs[min_index]
      total_costs[min_index] = tmp_cost
      let tmp_node = node_indexes[i]
      node_indexes[i] = node_indexes[min_index]
      node_indexes[min_index] = tmp_node
      let tmp_path = path_indexes[i]
      path_indexes[i] = path_indexes[min_index]
      path_indexes[min_index] = tmp_path
    }
  }
}

///|
fn reconstruct_path(
  input : String,
  utf16_offsets : Array[Int],
  nodes : Array[@types.LatticeNode],
  pos_detail_pool : Array[String],
  mecab_feature_pool : Array[String],
  node_path_prev_nodes : Array[Array[Int]],
  node_path_prev_path_indexes : Array[Array[Int]],
  tail_node_index : Int,
  tail_path_index : Int,
) -> Array[@types.Morpheme] {
  let mut len_cursor_node = tail_node_index
  let mut len_cursor_path = tail_path_index
  let mut path_len = 0
  while len_cursor_node > 0 {
    path_len = path_len + 1
    let prev_nodes = node_path_prev_nodes[len_cursor_node]
    let prev_paths = node_path_prev_path_indexes[len_cursor_node]
    let next_node = prev_nodes[len_cursor_path]
    let next_path = prev_paths[len_cursor_path]
    len_cursor_node = next_node
    len_cursor_path = next_path
  }
  let path : Array[@types.Morpheme] = Array::makei(path_len, _ => {
    surface: "",
    pos: @types.POS::Unknown,
    pos_detail: "",
    mecab_feature: "",
    start_pos: 0,
    end_pos: 0,
  })
  let mut cursor_node = tail_node_index
  let mut cursor_path = tail_path_index
  let mut write_index = path_len - 1
  while cursor_node > 0 {
    let node = nodes[cursor_node]
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
    let prev_nodes = node_path_prev_nodes[cursor_node]
    let prev_paths = node_path_prev_path_indexes[cursor_node]
    let next_node = prev_nodes[cursor_path]
    let next_path = prev_paths[cursor_path]
    cursor_node = next_node
    cursor_path = next_path
    write_index = write_index - 1
  }
  path
}

///|
pub fn decode_viterbi_nbest_with_classes(
  input : String,
  classes : Array[@types.CharClass],
  n : Int,
  options : @types.ParseOptions,
) -> Array[@types.NBestResult] {
  if n <= 0 {
    return []
  }
  let chars = input.to_array()
  let run_lengths = build_class_run_lengths(classes)
  decode_viterbi_nbest_with_precomputed(
    input, chars, classes, run_lengths, n, options,
  )
}

///|
pub fn decode_viterbi_nbest_with_precomputed(
  input : String,
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
  n : Int,
  options : @types.ParseOptions,
) -> Array[@types.NBestResult] {
  if n <= 0 {
    return []
  }
  let text_len = chars.length()
  if text_len == 0 {
    return []
  }
  let run_lengths = if run_lengths.length() == text_len {
    run_lengths
  } else {
    build_class_run_lengths(classes)
  }
  let constraint = prepare_constraint(options.constraint, text_len)
  if !constraint.valid {
    return []
  }
  let nodes : Array[@types.LatticeNode] = Array::new(capacity=text_len * 4)
  let end_heads : Array[Int] = Array::makei(text_len + 1, _ => -1)
  let next_by_end : Array[Int] = Array::new(capacity=text_len * 4)
  let scratch_cands : Array[@types.TokenCandidate] = Array::new(capacity=16)
  let scratch_prev_indexes : Array[Int] = Array::new(capacity=16)
  let node_path_masks : Array[Array[Int]] = Array::new(capacity=text_len * 4)
  let node_path_costs : Array[Array[Int]] = Array::new(capacity=text_len * 4)
  let node_path_prev_nodes : Array[Array[Int]] = Array::new(
    capacity=text_len * 4,
  )
  let node_path_prev_path_indexes : Array[Array[Int]] = Array::new(
    capacity=text_len * 4,
  )
  let pos_detail_pool : Array[String] = Array::new(capacity=64)
  let mecab_feature_pool : Array[String] = Array::new(capacity=64)
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
  node_path_masks.push([0])
  node_path_costs.push([0])
  node_path_prev_nodes.push([-1])
  node_path_prev_path_indexes.push([-1])
  for pos in 0..<text_len {
    let head = end_heads[pos]
    if head < 0 {
      continue
    }
    scratch_prev_indexes.truncate(0)
    let mut cursor = head
    while cursor >= 0 {
      scratch_prev_indexes.push(cursor)
      cursor = next_by_end[cursor]
    }
    @lattice.candidates_at_into_with_run_lengths(
      scratch_cands, chars, classes, run_lengths, pos,
    )
    let cls = classes[pos]
    let run_len = run_lengths[pos]
    for cand in scratch_cands {
      if !is_candidate_allowed(constraint, cand) {
        continue
      }
      let token_len = cand.end_pos - cand.start_pos
      let emission_adj = @scorer.emission_adjustment(
        cand.pos,
        cls,
        token_len,
        run_len,
      )
      let pos_detail_id = intern_pos_detail(pos_detail_pool, cand.pos_detail)
      let mecab_feature_id = intern_pos_detail(
        mecab_feature_pool,
        cand.mecab_feature,
      )
      let delta_mask = candidate_required_mask_delta(
        constraint,
        cand.start_pos,
        cand.end_pos,
      )
      let node_index = nodes.length()
      nodes.push({
        start_pos: cand.start_pos,
        end_pos: cand.end_pos,
        pos: cand.pos,
        pos_detail_id,
        mecab_feature_id,
        right_id: cand.right_id,
        best_cost: 0,
        best_prev: -1,
      })
      next_by_end.push(-1)
      node_path_masks.push(Array::new(capacity=4))
      node_path_costs.push(Array::new(capacity=4))
      node_path_prev_nodes.push(Array::new(capacity=4))
      node_path_prev_path_indexes.push(Array::new(capacity=4))
      let path_masks = node_path_masks[node_index]
      let path_costs = node_path_costs[node_index]
      let path_prev_nodes = node_path_prev_nodes[node_index]
      let path_prev_path_indexes = node_path_prev_path_indexes[node_index]
      for prev_index in scratch_prev_indexes {
        let prev = nodes[prev_index]
        let transition_cost = @scorer.connection_cost(
            prev.right_id,
            cand.left_id,
          ) +
          cand.word_cost +
          emission_adj
        let prev_masks = node_path_masks[prev_index]
        let prev_costs = node_path_costs[prev_index]
        for prev_path_index in 0..<prev_masks.length() {
          insert_path_with_mask_limit(
            path_masks,
            path_costs,
            path_prev_nodes,
            path_prev_path_indexes,
            prev_masks[prev_path_index] | delta_mask,
            prev_costs[prev_path_index] + transition_cost,
            prev_index,
            prev_path_index,
            n,
          )
        }
      }
      if path_masks.length() > 0 && cand.end_pos < text_len {
        next_by_end[node_index] = end_heads[cand.end_pos]
        end_heads[cand.end_pos] = node_index
      }
    }
  }
  let final_node_indexes : Array[Int] = Array::new(capacity=n)
  let final_path_indexes : Array[Int] = Array::new(capacity=n)
  let final_total_costs : Array[Int] = Array::new(capacity=n)
  for node_index in 1..<nodes.length() {
    let node = nodes[node_index]
    if node.end_pos != text_len {
      continue
    }
    let path_masks = node_path_masks[node_index]
    let path_costs = node_path_costs[node_index]
    for path_index in 0..<path_masks.length() {
      if path_masks[path_index] != constraint.required_all_mask {
        continue
      }
      let total_cost = path_costs[path_index] +
        @scorer.connection_cost(node.right_id, bos_connection_id)
      insert_final_with_limit(
        final_node_indexes, final_path_indexes, final_total_costs, node_index, path_index,
        total_cost, n,
      )
    }
  }
  if final_node_indexes.is_empty() {
    return []
  }
  sort_final_by_cost(final_node_indexes, final_path_indexes, final_total_costs)
  let utf16_offsets = if input.length() == text_len {
    []
  } else {
    build_utf16_offsets(chars)
  }
  let results : Array[@types.NBestResult] = Array::new(
    capacity=final_node_indexes.length(),
  )
  for i in 0..<final_node_indexes.length() {
    let morphemes = reconstruct_path(
      input,
      utf16_offsets,
      nodes,
      pos_detail_pool,
      mecab_feature_pool,
      node_path_prev_nodes,
      node_path_prev_path_indexes,
      final_node_indexes[i],
      final_path_indexes[i],
    )
    results.push({ morphemes, total_cost: final_total_costs[i] })
  }
  results
}

///|
pub fn decode_viterbi_with_options_with_classes(
  input : String,
  classes : Array[@types.CharClass],
  options : @types.ParseOptions,
) -> Array[@types.Morpheme] {
  let chars = input.to_array()
  let run_lengths = build_class_run_lengths(classes)
  decode_viterbi_with_options_with_precomputed(
    input, chars, classes, run_lengths, options,
  )
}

///|
pub fn decode_viterbi_with_options_with_precomputed(
  input : String,
  chars : Array[Char],
  classes : Array[@types.CharClass],
  run_lengths : Array[Int],
  options : @types.ParseOptions,
) -> Array[@types.Morpheme] {
  if is_unconstrained(options.constraint) {
    return decode_viterbi_with_precomputed(input, chars, classes, run_lengths)
  }
  let results = decode_viterbi_nbest_with_precomputed(
    input, chars, classes, run_lengths, 1, options,
  )
  if results.is_empty() {
    []
  } else {
    results[0].morphemes
  }
}
