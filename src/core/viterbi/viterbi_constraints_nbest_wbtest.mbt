///|
fn has_cost(xs : Array[Int], target : Int) -> Bool {
  for x in xs {
    if x == target {
      return true
    }
  }
  false
}

///|
test "prepare_constraint should normalize and deduplicate values" {
  let raw = {
    ..@types.ParseConstraint::none(),
    must_break_positions: [0, 1, 1, 3],
    forbid_break_positions: [0, 2],
    must_cover_spans: [
      { start_pos: 1, end_pos: 2 },
      { start_pos: 1, end_pos: 2 },
    ],
  }
  let prepared = prepare_constraint(raw, 3)
  assert_true(prepared.valid)
  inspect(prepared.must_break_positions, content="[1]")
  inspect(prepared.forbid_break_positions, content="[2]")
  inspect(prepared.must_cover_spans.length(), content="1")
  inspect(prepared.required_all_mask, content="3")
}

///|
test "prepare_constraint should reject conflicting break constraints" {
  let raw = {
    ..@types.ParseConstraint::none(),
    must_break_positions: [1],
    forbid_break_positions: [1],
  }
  let prepared = prepare_constraint(raw, 2)
  inspect(prepared.valid, content="false")
}

///|
test "candidate_required_mask_delta should map break and span bits" {
  let prepared = prepare_constraint(
    {
      ..@types.ParseConstraint::none(),
      must_break_positions: [1, 2],
      must_cover_spans: [{ start_pos: 0, end_pos: 3 }],
    },
    3,
  )
  assert_true(prepared.valid)
  inspect(candidate_required_mask_delta(prepared, 0, 1), content="1")
  inspect(candidate_required_mask_delta(prepared, 1, 2), content="2")
  inspect(candidate_required_mask_delta(prepared, 0, 3), content="4")
}

///|
test "insert_path_with_mask_limit should keep cheapest paths per mask" {
  let masks : Array[Int] = []
  let costs : Array[Int] = []
  let prev_nodes : Array[Int] = []
  let prev_path_indexes : Array[Int] = []
  insert_path_with_mask_limit(
    masks, costs, prev_nodes, prev_path_indexes, 1, 10, 3, 0, 2,
  )
  insert_path_with_mask_limit(
    masks, costs, prev_nodes, prev_path_indexes, 1, 8, 4, 0, 2,
  )
  insert_path_with_mask_limit(
    masks, costs, prev_nodes, prev_path_indexes, 1, 15, 5, 0, 2,
  )
  assert_eq(masks.length(), 2)
  assert_true(has_cost(costs, 8))
  assert_true(has_cost(costs, 10))
  assert_true(!has_cost(costs, 15))
}

///|
test "is_candidate_allowed should respect pos and unknown restrictions" {
  let base_cand : @types.TokenCandidate = {
    start_pos: 0,
    end_pos: 1,
    pos: @types.POS::Particle,
    pos_detail: "助詞,*,*,*",
    mecab_feature: "助詞,*,*,*,*,*,*,*,*",
    left_id: 0,
    right_id: 0,
    word_cost: 0,
  }
  let allowed_only_noun = prepare_constraint(
    { ..@types.ParseConstraint::none(), allowed_pos: [@types.POS::NounGeneral] },
    2,
  )
  assert_true(allowed_only_noun.valid)
  assert_true(!is_candidate_allowed(allowed_only_noun, base_cand))
  let disallow_particle = prepare_constraint(
    { ..@types.ParseConstraint::none(), disallowed_pos: [@types.POS::Particle] },
    2,
  )
  assert_true(disallow_particle.valid)
  assert_true(!is_candidate_allowed(disallow_particle, base_cand))
  let unknown_cand : @types.TokenCandidate = {
    ..base_cand,
    pos: @types.POS::Unknown,
  }
  let no_unknown = prepare_constraint(
    { ..@types.ParseConstraint::none(), allow_unknown: false },
    2,
  )
  assert_true(no_unknown.valid)
  assert_true(!is_candidate_allowed(no_unknown, unknown_cand))
}
