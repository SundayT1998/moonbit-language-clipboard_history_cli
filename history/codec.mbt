///|
/// 转义：反斜杠、换行、制表、回车、竖线、`#` 开头需要处理。
fn escape_field(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn unescape_field(s : String) -> String {
  let out = StringBuilder()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && i + 1 < chars.length() {
      let n = chars[i + 1]
      if n == 'n' {
        out.write_char('\n')
      } else if n == 'r' {
        out.write_char('\r')
      } else if n == 't' {
        out.write_char('\t')
      } else if n == '\\' {
        out.write_char('\\')
      } else {
        out.write_char(c)
        out.write_char(n)
      }
      i = i + 2
      continue
    }
    out.write_char(c)
    i = i + 1
  }
  out.to_string()
}

///|
const FORMAT_HEADER : String = "mtuck-history\t1"

///|
/// 把历史编码成行式文本存储格式。每行六列，用 TAB 分隔：
/// `ts hits pinned kind is_secret text`
/// 选择这个格式而不是 JSON：省掉一个依赖，diff 友好，坏行可跳过。
pub fn encode(history : History) -> String {
  let out = StringBuilder()
  out.write_string(FORMAT_HEADER)
  out.write_char('\n')
  for e in history.entries {
    out.write_string(e.ts.to_string())
    out.write_char('\t')
    out.write_string(e.hits.to_string())
    out.write_char('\t')
    out.write_string(if e.pinned { "1" } else { "0" })
    out.write_char('\t')
    out.write_string(escape_field(e.kind_label))
    out.write_char('\t')
    out.write_string(if e.is_secret { "1" } else { "0" })
    out.write_char('\t')
    out.write_string(escape_field(e.text))
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn parse_int64(s : StringView) -> Int64? {
  Some(@string.parse_int64(s)) catch {
    _ => None
  }
}

///|
fn parse_int(s : StringView) -> Int32? {
  Some(@string.parse_int(s)) catch {
    _ => None
  }
}

///|
/// 解码历史。无法解析的行直接跳过，保证老版本数据不会把工具搞死。
pub fn decode(data : String) -> History {
  let history = History::new()
  let lines = data.split("\n").collect()
  let mut start = 0
  if !lines.is_empty() && lines[0].to_owned().has_prefix(FORMAT_HEADER) {
    start = 1
  }
  for line in lines[start:] {
    if line.trim().is_empty() {
      continue
    }
    let cols = line.split("\t").collect()
    if cols.length() < 6 {
      continue
    }
    let ts = parse_int64(cols[0])
    let hits = parse_int(cols[1])
    if ts is None || hits is None {
      continue
    }
    // 文本里可能有 TAB，所以只切前五列，后面的全部拼回文本
    let raw_text = StringBuilder()
    for i in 5..<cols.length() {
      if i > 5 {
        raw_text.write_char('\t')
      }
      raw_text.write_string(cols[i].to_owned())
    }
    let entry : Entry = {
      text: unescape_field(raw_text.to_string()),
      ts: ts.unwrap(),
      hits: hits.unwrap(),
      pinned: cols[2] == "1",
      kind_label: unescape_field(cols[3].to_owned()),
      is_secret: cols[4] == "1",
    }
    history.entries.push(entry)
  }
  history
}
