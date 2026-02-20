///|
pub fn decode_viterbi_with_classes(
  input : String,
  classes : Array[@types.CharClass],
  edition : Int,
) -> Array[@types.Morpheme] {
  let chars = input.to_array()
  let text_len = chars.length()
  if text_len == 0 {
    return []
  }
  let nodes : Array[@types.LatticeNode] = Array::new(capacity=text_len * 4)
  let end_heads : Array[Int] = Array::makei(text_len + 1, _ => -1)
  let next_by_end : Array[Int] = Array::new(capacity=text_len * 4)
  let scratch_cands : Array[@types.TokenCandidate] = Array::new(capacity=16)
  nodes.push({
    start_pos: 0,
    end_pos: 0,
    pos: @types.POS::BosEos,
    pos_detail: "BOS/EOS,*,*,*",
    left_id: 0,
    right_id: 0,
    word_cost: 0,
    best_cost: 0,
    best_prev: -1,
  })
  next_by_end.push(-1)
  end_heads[0] = 0
  for pos in 0..<text_len {
    @lattice.candidates_at_into(scratch_cands, chars, classes, pos, edition)
    let head = end_heads[pos]
    if head < 0 {
      continue
    }
    for cand in scratch_cands {
      let mut best_cost = @int.max_value
      let mut best_prev = -1
      let mut cursor = head
      while cursor >= 0 {
        let prev = nodes[cursor]
        let cost = prev.best_cost +
          @scorer.connection_cost(prev.right_id, cand.left_id) +
          cand.word_cost
        if cost < best_cost {
          best_cost = cost
          best_prev = cursor
        }
        cursor = next_by_end[cursor]
      }
      if best_prev >= 0 {
        let node_index = nodes.length()
        nodes.push({
          start_pos: cand.start_pos,
          end_pos: cand.end_pos,
          pos: cand.pos,
          pos_detail: cand.pos_detail,
          left_id: cand.left_id,
          right_id: cand.right_id,
          word_cost: cand.word_cost,
          best_cost,
          best_prev,
        })
        next_by_end.push(end_heads[cand.end_pos])
        end_heads[cand.end_pos] = node_index
      }
    }
  }
  let mut eos_best_cost = @int.max_value
  let mut eos_best_prev = -1
  let mut eos_cursor = end_heads[text_len]
  while eos_cursor >= 0 {
    let prev = nodes[eos_cursor]
    let cost = prev.best_cost + @scorer.connection_cost(prev.right_id, 0)
    if cost < eos_best_cost {
      eos_best_cost = cost
      eos_best_prev = eos_cursor
    }
    eos_cursor = next_by_end[eos_cursor]
  }
  if eos_best_prev < 0 {
    return []
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
    start_pos: 0,
    end_pos: 0,
  })
  let mut cursor = eos_best_prev
  let mut write_index = path_len - 1
  while cursor > 0 {
    let node = nodes[cursor]
    path[write_index] = {
      surface: @types.chars_slice(chars, node.start_pos, node.end_pos),
      pos: node.pos,
      pos_detail: node.pos_detail,
      start_pos: node.start_pos,
      end_pos: node.end_pos,
    }
    cursor = node.best_prev
    write_index = write_index - 1
  }
  path
}
