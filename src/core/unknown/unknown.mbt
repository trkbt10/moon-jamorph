///|
pub fn append_unknown_candidates_with_run_len(
  dst : Array[@types.TokenCandidate],
  classes : Array[@types.CharClass],
  pos : Int,
  run_len : Int,
) -> Unit {
  let noun_conn_id = @runtime.noun_connection_index()
  let unknown_conn_id = @runtime.unknown_connection_index()
  let cat = classes[pos]
  let run_len = if run_len > 0 { run_len } else { 1 }
  match cat {
    @types.CharClass::Katakana =>
      for len in 1..<=run_len {
        dst.push({
          start_pos: pos,
          end_pos: pos + len,
          pos: @types.POS::NounProper,
          pos_detail: "名詞,固有名詞,未知語,*",
          mecab_feature: "名詞,固有名詞,未知語,*,*,*,*,*,*",
          left_id: noun_conn_id,
          right_id: noun_conn_id,
          word_cost: 7000,
        })
      }
    @types.CharClass::AsciiAlpha => {
      dst.push({
        start_pos: pos,
        end_pos: pos + run_len,
        pos: @types.POS::NounProper,
        pos_detail: "名詞,固有名詞,未知語,*",
        mecab_feature: "名詞,固有名詞,未知語,*,*,*,*,*,*",
        left_id: noun_conn_id,
        right_id: noun_conn_id,
        word_cost: 7600,
      })
      dst.push({
        start_pos: pos,
        end_pos: pos + 1,
        pos: @types.POS::Unknown,
        pos_detail: "未知語,英字,*,*",
        mecab_feature: "未知語,英字,*,*,*,*,*,*,*",
        left_id: unknown_conn_id,
        right_id: unknown_conn_id,
        word_cost: 10000,
      })
    }
    @types.CharClass::AsciiDigit => {
      dst.push({
        start_pos: pos,
        end_pos: pos + run_len,
        pos: @types.POS::NounGeneral,
        pos_detail: "名詞,数,*,*",
        mecab_feature: "名詞,数,*,*,*,*,*,*,*",
        left_id: noun_conn_id,
        right_id: noun_conn_id,
        word_cost: 7300,
      })
      dst.push({
        start_pos: pos,
        end_pos: pos + 1,
        pos: @types.POS::Unknown,
        pos_detail: "未知語,数字,*,*",
        mecab_feature: "未知語,数字,*,*,*,*,*,*,*",
        left_id: unknown_conn_id,
        right_id: unknown_conn_id,
        word_cost: 10000,
      })
    }
    @types.CharClass::Kanji => {
      let max_len = if run_len < 8 { run_len } else { 8 }
      for len in 1..<=max_len {
        dst.push({
          start_pos: pos,
          end_pos: pos + len,
          pos: @types.POS::NounGeneral,
          pos_detail: "名詞,一般,未知語,*",
          mecab_feature: "名詞,一般,未知語,*,*,*,*,*,*",
          left_id: noun_conn_id,
          right_id: noun_conn_id,
          word_cost: 8000,
        })
      }
    }
    @types.CharClass::Hiragana => {
      let max_len = if run_len < 2 { run_len } else { 2 }
      for len in 1..<=max_len {
        dst.push({
          start_pos: pos,
          end_pos: pos + len,
          pos: @types.POS::Unknown,
          pos_detail: "未知語,ひらがな,*,*",
          mecab_feature: "未知語,ひらがな,*,*,*,*,*,*,*",
          left_id: unknown_conn_id,
          right_id: unknown_conn_id,
          word_cost: 9600,
        })
      }
    }
    @types.CharClass::Symbol =>
      dst.push({
        start_pos: pos,
        end_pos: pos + 1,
        pos: @types.POS::Unknown,
        pos_detail: "未知語,記号,*,*",
        mecab_feature: "未知語,記号,*,*,*,*,*,*,*",
        left_id: unknown_conn_id,
        right_id: unknown_conn_id,
        word_cost: 11000,
      })
    _ =>
      dst.push({
        start_pos: pos,
        end_pos: pos + 1,
        pos: @types.POS::Unknown,
        pos_detail: "未知語,その他,*,*",
        mecab_feature: "未知語,その他,*,*,*,*,*,*,*",
        left_id: unknown_conn_id,
        right_id: unknown_conn_id,
        word_cost: 10000,
      })
  }
}

///|
pub fn append_unknown_candidates(
  dst : Array[@types.TokenCandidate],
  classes : Array[@types.CharClass],
  pos : Int,
) -> Unit {
  let cat = classes[pos]
  let mut run_len = 1
  while pos + run_len < classes.length() && classes[pos + run_len] == cat {
    run_len = run_len + 1
  }
  append_unknown_candidates_with_run_len(dst, classes, pos, run_len)
}

///|
pub fn generate_unknown_candidates(
  classes : Array[@types.CharClass],
  pos : Int,
) -> Array[@types.TokenCandidate] {
  let candidates : Array[@types.TokenCandidate] = Array::new(capacity=8)
  append_unknown_candidates(candidates, classes, pos)
  candidates
}
