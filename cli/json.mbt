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
/// `list --json`：把选中的条目拼成 JSON 数组打出来。
fn print_json_entries(
  history : @history.History,
  indexes : Array[Int32],
  full~ : Bool,
) -> Unit {
  let out = StringBuilder()
  out.write_string("[")
  let mut first = true
  for idx in indexes {
    match history.get(idx) {
      None => ()
      Some(e) => {
        if !first {
          out.write_string(",")
        }
        first = false
        out.write_string("{\"index\":\{idx},\"ts\":\{e.ts},\"hits\":\{e.hits}")
        out.write_string(",\"pinned\":\{e.pinned},\"kind\":\"\{e.kind_label}\"")
        out.write_string(",\"secret\":\{e.is_secret}")
        // 与列表视图一致：密钥默认打码，`-f` 才输出原文
        let text = if e.is_secret && !full {
          @history.mask(@history.summary(e.text, 24))
        } else {
          e.text
        }
        out.write_string(",\"redacted\":\{(text != e.text)}")
        out.write_string(",\"text\":\"\{json_escape(text)}\"}")
      }
    }
  }
  out.write_string("]")
  println(out.to_string())
}

///|
/// `stats --json`：条目规模、类型分布和存储路径。
fn print_json_stats(stats : Stats, path : String) -> Unit {
  let out = StringBuilder()
  out.write_string("{\"total\":\{stats.total}")
  out.write_string(",\"pinned\":\{stats.pinned},\"secret\":\{stats.secrets}")
  out.write_string(",\"chars\":\{stats.chars}")
  out.write_string(",\"bytes\":\{stats.bytes}")
  out.write_string(",\"path\":\"\{json_escape(path)}\"")
  out.write_string(",\"kinds\":{")
  let mut first = true
  for k, v in stats.kinds {
    if !first {
      out.write_string(",")
    }
    first = false
    out.write_string("\"\{json_escape(k)}\":\{v}")
  }
  out.write_string("}}")
  println(out.to_string())
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
