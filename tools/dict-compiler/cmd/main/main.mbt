///|
fn main {
  let sample_tsv = "東京\tNOUN_PROPER\t1\t1\t600\n大学\tNOUN_GENERAL\t1\t1\t700\n"
  let out = @compiler.compile_tsv_to_entries_module_for_edition(
    sample_tsv, "mini_extra_entries", "mini",
  )
  let trie_out = @compiler.compile_tsv_to_da_trie_module_for_edition(
    sample_tsv, "mini_trie", "mini",
  )
  println(out + "\n" + trie_out)
}
