///|
/// 剪贴板内容的类型判定结果。
/// `label` 用于 UI 简短说明，`is_secret` 决定会不会被打码。
pub(all) struct Kind {
  label : String
  is_secret : Bool
}

///|
let secret_kind : Kind = { label: "secret", is_secret: true, }

///|
let text_kind : Kind = { label: "text", is_secret: false, }

///|
fn lower_ascii(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      out.write_char(Int32::unsafe_to_char(c.to_int() + 32))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn starts_with_ci(s : StringView, prefix : String) -> Bool {
  let text = s.to_owned()
  if text.length() < prefix.length() {
    return false
  }
  lower_ascii(text[:prefix.length()].to_owned()) == prefix
}

///|
fn contains_any_ci(s : StringView, needles : Array[String]) -> Bool {
  let low = lower_ascii(s.to_owned())
  needles.any(fn(n) { low.contains(n) })
}

///|
/// 取 `scheme://...` 里小写化的 scheme，没有则返回空串。
fn scheme_of_token(token : StringView) -> String {
  let text = token.to_owned()
  match text.find("://") {
    Some(idx) => lower_ascii(text[:idx].to_owned())
    None => ""
  }
}

///|
fn sensitive_keywords() -> Array[String] {
  [
    "password", "passwd", "pwd", "secret", "token", "api_key", "apikey", "access_key",
    "private_key", "credential", "authorization", "bearer",
  ]
}

///|
/// 裸密钥的前缀特征（小写比较），出现在任意位置都算密钥。
fn secret_markers() -> Array[String] {
  [
    "bearer ", "sk-", "ghp_", "gho_", "ghs_", "github_pat_", "akia", "xoxb-", "xoxp-",
  ]
}

///|
/// `user:pass@` 形式的账号密码：`@` 前面同一段里要有冒号。
fn has_userinfo(s : StringView) -> Bool {
  let text = s.to_owned()
  let mut seg = StringBuilder()
  for c in text {
    if c == '@' {
      let part = seg.to_string()
      if part.contains(":") && !part.contains("/") {
        return true
      }
      seg = StringBuilder()
    } else if c == '/' {
      seg = StringBuilder()
    } else {
      seg.write_char(c)
    }
  }
  false
}

///|
/// 判定一段剪贴板文本的类型：单行优先看结构（URL / JWT / 私钥 / 密钥赋值），
/// 多行只在最后一行是密钥赋值时才算密钥。
pub fn classify(text : String) -> Kind {
  let trimmed = text.trim()
  if trimmed.is_empty() {
    return { label: "empty", is_secret: false, }
  }
  if contains_any_ci(trimmed, ["-----begin", "private key"]) {
    return secret_kind
  }
  // 敏感子串优先于 URL / DSN 结构判定：`https://x/?token=...`、
  // `authorization: bearer ...`、裸 `sk-...` 都必须在打码范围内。
  if contains_any_ci(trimmed, secret_markers()) ||
    contains_any_ci(trimmed, ["token=", "token:", "password=", "passwd="]) {
    return secret_kind
  }
  let words = sensitive_keywords()
  if !trimmed.contains("\n") {
    let first = match trimmed.split(" ").next() {
      Some(w) => w
      None => trimmed
    }
    let scheme = scheme_of_token(first)
    if scheme != "" {
      // `scheme://user:pass@host` 的连接串算密钥，纯 URL 不算
      if has_userinfo(first) {
        return secret_kind
      }
      let plain : Array[String] = ["http", "https", "ftp", "file", "mailto"]
      if plain.contains(scheme) {
        return { label: "url", is_secret: false, }
      }
      return { label: "dsn", is_secret: false, }
    }
    if starts_with_ci(trimmed, "eyj") && trimmed.split(".").count() == 3 {
      return { label: "jwt", is_secret: true, }
    }
    match trimmed.find("=") {
      Some(eq) if eq > 0 =>
        if words.any(fn(k) { lower_ascii(trimmed[:eq].to_owned()).contains(k) }) {
          return secret_kind
        }
      _ => ()
    }
    return text_kind
  }
  let lines = trimmed.split("\n").collect()
  let last = match lines.get(lines.length() - 1) {
    Some(line) => line
    None => trimmed
  }
  if last.contains("=") && contains_any_ci(last, words) {
    return secret_kind
  }
  text_kind
}

///|
/// 打码：保留开头几个字符，其余用 `•` 覆盖，最多再显示 8 个点。
pub fn mask(text : String) -> String {
  let chars = text.to_array()
  let keep = if chars.length() <= 6 { 1 } else { 4 }
  let out = StringBuilder()
  for i in 0..<keep.min(chars.length()) {
    out.write_char(chars[i])
  }
  let hidden = (chars.length() - keep).min(8)
  for _ in 0..<hidden {
    out.write_char('•')
  }
  out.to_string()
}
