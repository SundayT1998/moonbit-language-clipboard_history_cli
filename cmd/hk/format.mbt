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
/// `@env.now()` 返回的是**微秒**，先降到毫秒再转 `Int64`。
pub fn now_ms() -> Int64 {
  let nanos = @env.now()
  (nanos / 1000UL).reinterpret_as_int64()
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
          out.write_string("\\u00")
          out.write_char(if c.to_int() < 0x10 { '0' } else { '0' })
        } else {
          out.write_char(c)
        }
    }
  }
  out.to_string()
}
