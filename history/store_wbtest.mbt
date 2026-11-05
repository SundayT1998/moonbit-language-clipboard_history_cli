///|
fn mk() -> History {
  History::new()
}

///|
test "push 去重与 hits 累计" {
  let h = mk()
  assert_eq(h.push("a", 1L), Some(0))
  assert_eq(h.push("a", 2L), Some(0))
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().hits, 2)
}

///|
test "push 重复内容提到最前" {
  let h = mk()
  h.push("first", 1L) |> ignore
  h.push("second", 2L) |> ignore
  h.push("first", 3L) |> ignore
  assert_eq(h.len(), 2)
  assert_eq(h.get(0).unwrap().text, "first")
  assert_eq(h.get(0).unwrap().hits, 2)
}

///|
test "push 忽略空与超长内容" {
  let h = mk()
  assert_eq(h.push("   ", 1L), None)
  assert_eq(h.push("12345", 1L, max_bytes=4), None)
  assert_eq(h.len(), 0)
}

///|
test "固定条目不参与合并、不被裁掉" {
  let h = mk()
  h.push("pinned", 1L) |> ignore
  h.toggle_pin(0)
  h.push("pinned", 2L) |> ignore
  assert_eq(h.len(), 2)
  assert_eq(h.get(0).unwrap().pinned, false)
  assert_eq(h.get(1).unwrap().pinned, true)
  h.clear(keep_pinned=true)
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().text, "pinned")
}

///|
test "超过上限时淘汰最旧的未固定条目" {
  let h = mk()
  for i in 0..<(max_entries + 5) {
    h.push("item-\{i}", i.to_int64()) |> ignore
  }
  assert_eq(h.len(), max_entries)
  // 头部就是最后写入的那条
  assert_eq(h.get(0).unwrap().text, "item-\{max_entries + 4}")
  assert_eq(h.get(0).unwrap().hits, 1)
  assert_true(h.search("item-0").is_empty())
}

///|
test "search 与 remove_at" {
  let h = mk()
  h.push("alpha", 1L) |> ignore
  h.push("beta", 2L) |> ignore
  h.push("alphabet", 3L) |> ignore
  assert_eq(h.search("alpha").length(), 2)
  h.remove_at(0)
  assert_eq(h.len(), 2)
  assert_eq(h.get(0).unwrap().text, "beta")
}

///|
test "summary 折叠空白并截断" {
  assert_eq(summary("a\n\n  b\tc", 20), "a b c")
  assert_eq(summary("abcdefgh", 3), "abc…")
}
