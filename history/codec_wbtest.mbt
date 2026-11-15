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

///|
test "escape 覆盖反斜杠、回车与制表" {
  let h = History::new()
  h.push("a\\b\r\nc\td", 1L) |> ignore
  let text = encode(h)
  // 原始换行只出现在行尾：表头一个，条目一个。内容里的换行 / 回车 / TAB
  // 都被转义，不会多出来
  assert_eq(text.split("\n").collect().length(), 3)
  assert_false(text.contains("\r"))
  let back = decode(text)
  assert_eq(back.get(0).unwrap().text, "a\\b\nc\td")
}

///|
test "decode 把第一个 TAB 之后的列拼回文本" {
  let h = decode("100\t2\t1\turl\t0\thttps://a\tb\tc\n")
  let e = h.get(0).unwrap()
  assert_eq(e.text, "https://a\tb\tc")
  assert_eq(e.ts, 100L)
  assert_eq(e.hits, 2)
  assert_eq(e.kind_label, "url")
  assert_true(e.pinned)
  assert_false(e.is_secret)
}

///|
test "decode 跳过数值解析失败与空行" {
  let data = "mtuck-history\t1\nabc\t1\t0\ttext\t0\thits-bad\n1\tx\t0\ttext\t0\thits-bad\n\n   \n1\t1\t0\ttext\t0\tok\n"
  let h = decode(data)
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().text, "ok")
}

///|
test "decode 空数据与只有表头" {
  assert_eq(decode("").len(), 0)
  assert_eq(decode("mtuck-history\t1\n").len(), 0)
}

///|
test "decode 未来版本的未知键值对仍能读" {
  // 第 6 列之后都是文本；带 = 的高亮 / 来源信息不会被吞
  let h = decode("mtuck-history\t1\n5\t1\t0\ttext\t0\tkey=value\n")
  assert_eq(h.get(0).unwrap().text, "key=value")
}

///|
test "encode 空历史只有表头" {
  assert_eq(encode(History::new()), "mtuck-history\t1\n")
}

///|
test "往返保持顺序、固定与密钥标记" {
  let h = History::new()
  h.push("one", 1L) |> ignore
  h.push("password=x", 2L) |> ignore
  h.push("two", 3L) |> ignore
  h.toggle_pin(2)
  let back = decode(encode(h))
  assert_eq(back.len(), 3)
  assert_eq(back.get(0).unwrap().text, "two")
  assert_eq(back.get(1).unwrap().text, "password=x")
  assert_true(back.get(1).unwrap().is_secret)
  assert_eq(back.get(2).unwrap().text, "one")
  assert_true(back.get(2).unwrap().pinned)
}

///|
test "unescape 遇到未知转义与结尾反斜杠保持原样" {
  let h = decode("1\t1\t0\ttext\t0\ta\\qb\\\n")
  assert_eq(h.get(0).unwrap().text, "a\\qb\\")
}
