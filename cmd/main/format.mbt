///|
/// 相对时间：刚刚 / 3 分钟前 / 2 小时前 / 5 天前。
fn format_ago(ms : Int64, now_ms : Int64) -> String {
  let delta = now_ms - ms
  let seconds = delta / 1000L
  if seconds < 60L {
    "刚刚"
  } else if seconds < 3600L {
    "\{seconds / 60L} 分钟前"
  } else if seconds < 86400L {
    "\{seconds / 3600L} 小时前"
  } else {
    "\{seconds / 86400L} 天前"
  }
}

///|
/// 当前 Unix 时间（毫秒）。
///
/// `@env.now()` 返回的就是毫秒级 Unix 时间，直接转 `Int64` 即可。
pub fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
/// JSON 字符串转义。
fn json_escape(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          let hex = "0123456789abcdef"
          let n = c.to_int()
          out.write_string("\\u00")
          out.write_char(hex[(n / 16) & 0xF].unsafe_to_char())
          out.write_char(hex[n & 0xF].unsafe_to_char())
        } else {
          out.write_char(c)
        }
    }
  }
  out.to_string()
}

///|
test "now_ms 是毫秒级 Unix 时间" {
  // 2023-11 之后、3000 年之前：量级正确就落在这个区间
  assert_true(now_ms() > 1_700_000_000_000L)
  assert_true(now_ms() < 32_503_680_000_000L)
}

///|
test "json_escape 控制字符" {
  let esc = json_escape
  assert_eq(esc("a\u{01}").length(), 7)
  assert_eq(esc("a\u{01}"), "a" + "\\u0001")
  assert_eq(esc("a\u{00}"), "a" + "\\u0000")
  assert_eq(esc("a\u{09}"), "a" + "\\t")
  assert_eq(esc("a\u{0f}"), "a" + "\\u000f")
  assert_eq(esc("b\u{1f}c"), "b" + "\\u001f" + "c")
  assert_eq(esc("q\"\\\n\r\t"), "q" + "\\\"" + "\\\\" + "\\n" + "\\r" + "\\t")
}
