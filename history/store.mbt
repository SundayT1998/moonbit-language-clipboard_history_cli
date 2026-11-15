///|
/// 一条剪贴板历史。
pub(all) struct Entry {
  text : String
  /// 首次出现时间（毫秒）
  ts : Int64
  /// 重复复制次数
  hits : Int32
  /// 固定条目不会被上限淘汰、也不参与同内容合并
  pinned : Bool
  kind_label : String
  is_secret : Bool
}

///|
/// 单条内容上限（UTF-8 编码后的真实字节数，不是字符数）
pub let max_entry_bytes : Int32 = 256 * 1024

///|
/// 历史上限，超出后从最旧的未固定条目开始丢。
pub let max_entries : Int32 = 1000

///|
fn normalize_text(text : String) -> String {
  text.replace(old="\r\n", new="\n").trim().to_owned()
}

///|
/// 便于 UI 显示的单行摘要：折叠空白、截断到 `max_chars`。
pub fn summary(text : String, max_chars : Int32) -> String {
  let out = StringBuilder()
  let mut count = 0
  let mut space = false
  for c in text {
    if c == '\n' || c == '\r' || c == '\t' || c == ' ' {
      space = true
      continue
    }
    if space && count > 0 {
      out.write_char(' ')
      count = count + 1
    }
    space = false
    if count >= max_chars {
      out.write_string("…")
      break
    }
    out.write_char(c)
    count = count + 1
  }
  out.to_string()
}

///|
/// 历史列表。头部是最新的一条。
pub(all) struct History {
  mut entries : Array[Entry]
}

///|
pub fn History::new() -> History {
  { entries: [], }
}

///|
pub fn History::len(self : History) -> Int32 {
  self.entries.length()
}

///|
pub fn History::is_empty(self : History) -> Bool {
  self.entries.is_empty()
}

///|
/// 清空。`keep_pinned` 为真时保留固定条目。
pub fn History::clear(self : History, keep_pinned~ : Bool = false) -> Unit {
  if keep_pinned {
    self.entries = self.entries.iter().filter(fn(e) { e.pinned }).collect()
  } else {
    self.entries = []
  }
}

///|
/// 写入一条新内容，返回它最终的下标（0 = 最新）。
///
/// 规则：
/// - 空内容、超长内容忽略，返回 `None`；
/// - 与最新一条相同 → hits + 1；
/// - 与更早的未固定条目相同 → 合并（hits + 1）并提到最前；
/// - 固定条目不参与合并。
pub fn History::push(
  self : History,
  text : String,
  now_ms : Int64,
  max_bytes~ : Int32 = max_entry_bytes,
) -> Int32? {
  let norm = normalize_text(text)
  if norm.is_empty() || @utf8.encode(norm).length() > max_bytes {
    return None
  }
  let kind = classify(norm)
  if !self.entries.is_empty() {
    let head = self.entries[0]
    if !head.pinned &&
      head.text == norm &&
      head.kind_label == kind.label &&
      head.is_secret == kind.is_secret {
      self.entries[0] = { ..head, hits: head.hits + 1, }
      return Some(0)
    }
  }
  let merged = self.entries.search_by(fn(e) {
    !e.pinned && e.text == norm && e.is_secret == kind.is_secret
  })
  match merged {
    Some(idx) => {
      let old = self.entries[idx]
      let fresh : Entry = {
        text: old.text,
        ts: old.ts,
        hits: old.hits + 1,
        pinned: false,
        kind_label: kind.label,
        is_secret: kind.is_secret,
      }
      self.entries.remove(idx) |> ignore
      self.entries.insert(0, fresh)
      Some(0)
    }
    None => {
      let entry = make_entry(norm, now_ms, kind)
      self.entries.insert(0, entry)
      self.trim()
      Some(0)
    }
  }
}

///|
/// 构造一条未固定的新条目。
fn make_entry(text : String, now_ms : Int64, kind : Kind) -> Entry {
  {
    text,
    ts: now_ms,
    hits: 1,
    pinned: false,
    kind_label: kind.label,
    is_secret: kind.is_secret,
  }
}

///|
/// 超过上限时丢掉最旧的未固定条目。只有真的删掉了条目才重新绑定字段。
///
/// 注意：不删的时候**不要**写 `self.entries = ...`。`entries` 是 mut 字段，
/// 任何赋值都可能拿到一份 `trim_entries` 里被复制过的新数组，而调用方手里
/// 正在遍历的旧快照会和新数组脱钩——满载时插一条就丢一条，实测踩到过。
fn History::trim(self : History) -> Unit {
  if self.entries.length() <= max_entries {
    return
  }
  let trimmed = trim_entries(self.entries)
  if trimmed.length() != self.entries.length() {
    self.entries = trimmed
  }
}

///|
/// 把条目表砍到上限以内：从尾部倒着扫一遍，删掉最旧的未固定条目。
///
/// 注意：这里刻意不用 `search_by`，那条路径在满载时会把刚插入的头部
/// 换掉（在 1000 条满载的边界上实测踩到过）。从尾部倒着找，行为可预测。
///
/// 满上限之后每个新条目都要走一遍这里，所以不超限时直接返回原数组，
/// 只在**第一次真删**时复制一份：正常情况下都是原地删除。
fn trim_entries(entries : Array[Entry]) -> Array[Entry] {
  if entries.length() <= max_entries {
    return entries
  }
  // 先只找要删的下标，一个都不删就不复制数组
  let victims : Array[Int32] = []
  let excess = entries.length() - max_entries
  // `i` 单独声明：循环的起始值会先被当成 `i - 1` 求值，复用同一个变量会
  // 把长度减一，导致少删一条
  let mut i = entries.length() - 1
  while i >= 0 && victims.length() < excess {
    if !entries[i].pinned {
      victims.push(i)
    }
    i = i - 1
  }
  if victims.is_empty() {
    return entries
  }
  // 降序删除：先删后面的，前面的下标就不会变
  let result = entries.copy()
  for v in victims {
    result.remove(v) |> ignore
  }
  result
}

///|
pub fn History::get(self : History, index : Int32) -> Entry? {
  if index < 0 || index >= self.entries.length() {
    return None
  }
  Some(self.entries[index])
}

///|
pub fn History::remove_at(self : History, index : Int32) -> Unit {
  if index >= 0 && index < self.entries.length() {
    self.entries.remove(index) |> ignore
  }
}

///|
pub fn History::toggle_pin(self : History, index : Int32) -> Unit {
  if index >= 0 && index < self.entries.length() {
    let e = self.entries[index]
    self.entries[index] = { ..e, pinned: !e.pinned, }
  }
}

///|
/// 按子串搜索，返回命中的下标（保持原有顺序）。
pub fn History::search(self : History, query : String) -> Array[Int32] {
  let found = []
  for i, e in self.entries {
    if e.text.contains(query) {
      found.push(i)
    }
  }
  found
}
