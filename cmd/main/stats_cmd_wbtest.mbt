///|
test "compute_stats: 条目、固定、密钥与类型分布" {
  let h = sample_history()
  let stats = compute_stats(h)
  assert_eq(stats.total, 4)
  assert_eq(stats.pinned, 1)
  assert_eq(stats.secrets, 1)
  assert_eq(stats.kinds.get("url"), Some(1))
  assert_eq(stats.kinds.get("secret"), Some(1))
  assert_eq(stats.kinds.get("text"), Some(2))
}

///|
test "compute_stats: 字符数与 UTF-8 字节数分开统计" {
  let h = @history.History::new()
  // 三个汉字：3 个字符、9 个 UTF-8 字节
  h.push("中文字", 1L) |> ignore
  let stats = compute_stats(h)
  assert_eq(stats.chars, 3)
  assert_eq(stats.bytes, 9)
}

///|
test "compute_stats: 空历史" {
  let stats = compute_stats(@history.History::new())
  assert_eq(stats.total, 0)
  assert_eq(stats.chars, 0)
  assert_eq(stats.bytes, 0)
  assert_true(stats.kinds.is_empty())
}
