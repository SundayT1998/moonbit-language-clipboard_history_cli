///|
fn mk() -> History {
  History::new()
}

///|

///|
fn tail_texts(h : History, n : Int32) -> Array[String] {
  let out = []
  let start = if h.len() > n { h.len() - n } else { 0 }
  for i in start..<h.len() {
    out.push(h.get(i).unwrap().text)
  }
  out
}

///|
/// 快进到历史刚好装满：`max_entries` 条互不相同的未固定条目。
///
/// 先塞一条占位条目把长度撑到 `max_entries`，再直接替换成真实条目，
/// 最后删掉占位——全程只有 O(n) 次写入，不会因为逐条 `push` 触发淘汰。
fn History::push_until_full(self : History, now_ms : Int64) -> Unit {
  let placeholder = make_entry("mtuck-test-placeholder", now_ms, text_kind)
  while self.entries.length() < max_entries {
    self.entries.push(placeholder)
  }
  // 先把要保留的旧条目（比如固定条目）挪到暂存区，再整段重写；最后放回来
  let kept = self.entries.iter().filter(fn(e) { e.pinned }).collect()
  for i, e in self.entries {
    if !e.pinned {
      self.entries[i] = {
        ..e,
        text: "mtuck-test-entry-\{i}",
        ts: now_ms + i.to_int64(),
      }
    }
  }
  for k in kept {
    self.entries.push(k)
  }
  self.trim()
}

///|
fn head_texts(h : History, n : Int32) -> Array[String] {
  let out = []
  for i in 0..<n.min(h.len()) {
    out.push(h.get(i).unwrap().text)
  }
  out
}

///|
fn full_history() -> History {
  let h = History::new()
  h.push_until_full(0L)
  h
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

///|
test "push 前先规范化：\\r\\n 与首尾空白" {
  let h = mk()
  h.push("  hello\r\nworld  ", 1L) |> ignore
  h.push("hello\nworld", 2L) |> ignore
  // 规范化后内容相同 → 合并，而不是两条
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().text, "hello\nworld")
  assert_eq(h.get(0).unwrap().hits, 2)
}

///|
test "push 新条目记录分类结果与时间" {
  let h = mk()
  h.push("https://example.com", 42L) |> ignore
  let e = h.get(0).unwrap()
  assert_eq(e.kind_label, "url")
  assert_false(e.is_secret)
  assert_eq(e.ts, 42L)
  assert_false(e.pinned)
}

///|
test "push 合并时保留首次出现时间并更新分类" {
  let h = mk()
  h.push("a", 10L) |> ignore
  h.push("password=x", 20L) |> ignore
  h.push("a", 30L) |> ignore
  let e = h.get(0).unwrap()
  assert_eq(e.text, "a")
  assert_eq(e.ts, 10L)
  assert_eq(e.hits, 2)
  assert_eq(e.kind_label, "text")
}

///|
test "push 对固定条目头部不合并，另起一条" {
  let h = mk()
  h.push("same", 1L) |> ignore
  h.toggle_pin(0)
  h.push("same", 2L) |> ignore
  // 固定条目在后面不会被合并；新的一条在头部
  assert_eq(h.len(), 2)
  assert_eq(h.get(0).unwrap().pinned, false)
  assert_eq(h.get(0).unwrap().hits, 1)
  assert_true(h.get(1).unwrap().pinned)
}

///|
test "push 恰好等于上限的内容可以写入，多一字节则忽略" {
  let h = mk()
  // 4 个 ASCII 字符 = 4 字节
  assert_eq(h.push("abcd", 1L, max_bytes=4), Some(0))
  assert_eq(h.push("abcde", 1L, max_bytes=4), None)
  // 按 UTF-8 字节算：4 个中文字符 = 12 字节
  assert_eq(h.push("中文测试", 1L, max_bytes=11), None)
  assert_eq(h.push("中文测试", 1L, max_bytes=12), Some(0))
  assert_eq(h.len(), 2)
  assert_true(h.search("abcde").is_empty())
  assert_true(h.push("   ", 1L) is None)
}

///|
test "push 的长度上限按 UTF-8 字节而不是字符数" {
  let h = mk()
  // 纯 ASCII：上限就是字符数，不能按 ×4 提前拒绝
  let ascii = "a".repeat(100)
  assert_eq(h.push(ascii, 1L, max_bytes=100), Some(0))
  // 100 个中文字符 = 300 字节：按字符数算会被误拒，按字节算不会
  let cjk = "字".repeat(100)
  assert_eq(h.push(cjk, 1L, max_bytes=300), Some(0))
  assert_eq(h.push(cjk, 2L, max_bytes=299), None)
  // 4 字节的 emoji 也要按真实字节数算
  assert_eq(h.push("😀", 3L, max_bytes=4), Some(0))
  assert_eq(h.push("😀😀", 4L, max_bytes=7), None)
  // 换行会被规范成 `\n`（1 字节），`\r\n` 按 2 字节算的话会误拒
  assert_eq(h.push("abc\r\ndef", 5L, max_bytes=7), Some(0))
  assert_eq(h.len(), 4)
}

///|
test "clear 默认清空全部，keep_pinned 只留固定" {
  let h = mk()
  h.push("a", 1L) |> ignore
  h.push("b", 2L) |> ignore
  h.toggle_pin(1)
  h.clear()
  assert_true(h.is_empty())
  assert_eq(h.len(), 0)
  h.push("a", 3L) |> ignore
  h.push("b", 4L) |> ignore
  h.toggle_pin(1)
  h.clear(keep_pinned=true)
  assert_eq(h.len(), 1)
  assert_eq(h.get(0).unwrap().text, "a")
}

///|
test "固定条目在满载时也不被淘汰" {
  let h = mk()
  h.push("keep-me", 0L) |> ignore
  h.toggle_pin(0)
  h.push_until_full(1L)
  assert_eq(h.len(), max_entries)
  // 固定条目永远不被淘汰
  assert_true(h.get(0).unwrap().pinned)
  assert_eq(h.get(0).unwrap().text, "keep-me")
  assert_eq(head_texts(h, 2), ["keep-me", "mtuck-test-entry-1"])
  assert_eq(tail_texts(h, 2), ["mtuck-test-entry-998", "keep-me"])
  // 再插一条：淘汰的是最旧的未固定条目，固定条目还在
  h.push("more", 2L) |> ignore
  assert_eq(h.len(), max_entries)
  assert_eq(head_texts(h, 2), ["more", "keep-me"])
  assert_true(h.search("mtuck-test-entry-1").contains(2))
}

///|
test "只有固定条目时不再淘汰，长度可以超过上限" {
  // 一条固定条目 + 999 条未固定的满载历史
  let h = History::new()
  h.push_until_full(2L)
  h.entries[max_entries - 1] = { ..h.entries[max_entries - 1], pinned: true, }
  h.push("another", 3L) |> ignore
  assert_eq(h.len(), max_entries)
  assert_eq(h.get(0).unwrap().text, "another")
  // 固定条目还在
  assert_eq(h.entries.iter().filter(fn(e) { e.pinned }).count(), 1)
}

///|
test "满载后再插入：新条目在头部，最旧的未固定条目被淘汰" {
  let h = full_history()
  let oldest = h.get(max_entries - 1).unwrap().text
  h.push("brand-new", 99L) |> ignore
  assert_eq(h.len(), max_entries)
  assert_eq(h.get(0).unwrap().text, "brand-new")
  assert_true(h.search(oldest).is_empty())
  // 其余条目顺序保持不变：淘汰掉 entry-1，entry-0 被挤到第二
  assert_eq(head_texts(h, 3), [
    "brand-new", "mtuck-test-entry-0", "mtuck-test-entry-1",
  ])
  assert_eq(tail_texts(h, 2), ["mtuck-test-entry-997", "mtuck-test-entry-998"])
}

///|
test "get / remove_at / toggle_pin 越界是安全的空操作" {
  let h = mk()
  h.push("a", 1L) |> ignore
  assert_true(h.get(-1) is None)
  assert_true(h.get(1) is None)
  h.remove_at(-1)
  h.remove_at(5)
  h.toggle_pin(-1)
  h.toggle_pin(5)
  assert_eq(h.len(), 1)
  assert_false(h.get(0).unwrap().pinned)
}

///|
test "toggle_pin 来回切换" {
  let h = mk()
  h.push("a", 1L) |> ignore
  h.toggle_pin(0)
  assert_true(h.get(0).unwrap().pinned)
  h.toggle_pin(0)
  assert_false(h.get(0).unwrap().pinned)
}

///|
test "search 保持原顺序并支持空查询" {
  let h = mk()
  h.push("abc", 1L) |> ignore
  h.push("xyz", 2L) |> ignore
  h.push("ab", 3L) |> ignore
  // 最新在前：ab(#0) 是最后写入的，abc(#1)
  assert_eq(h.search("ab"), [0, 2])
  assert_eq(h.search(""), [0, 1, 2])
  assert_true(h.search("nope").is_empty())
}

///|
test "summary 的边界" {
  assert_eq(summary("", 10), "")
  assert_eq(summary("   ", 10), "")
  assert_eq(summary("abc", 3), "abc")
  assert_eq(summary("abc", 0), "…")
  // 首尾空白不产生前导 / 尾随空格
  assert_eq(summary("  a  b  ", 10), "a b")
  // 多字节字符按字符数截断
  assert_eq(summary("你好世界", 2), "你好…")
}

///|
test "push 满载时命中已有条目仍回到头部" {
  let h = full_history()
  assert_eq(h.push("mtuck-test-entry-500", 1000L), Some(0))
  assert_eq(h.len(), max_entries)
  assert_eq(h.get(0).unwrap().text, "mtuck-test-entry-500")
  assert_eq(h.get(0).unwrap().hits, 2)
}
