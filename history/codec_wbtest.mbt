///|
test "encode/decode 往返" {
  let h = History::new()
  h.push("multi\nline\ttext", 1700000000000L) |> ignore
  h.push("password=secret", 1700000001000L) |> ignore
  h.toggle_pin(0)
  let text = encode(h)
  let back = decode(text)
  assert_eq(back.len(), 2)
  let e = back.get(0).unwrap()
  assert_eq(e.text, "password=secret")
  assert_true(e.pinned)
  assert_true(e.is_secret)
  assert_eq(back.get(1).unwrap().text, "multi\nline\ttext")
  assert_eq(back.get(1).unwrap().ts, 1700000000000L)
}

///|
test "decode 跳过坏行且能吃没有表头的老数据" {
  let h = decode("1700000000000\t1\t0\ttext\t0\thello\nbad line\n")
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().text, "hello")
}
