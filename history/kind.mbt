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
/// 裸密钥的前缀特征。只按小写比较**前缀本身**，后面的格式另行校验，
/// 见 `has_secret_token`：`akia` / `sk-` 这类短前缀裸匹配会把
/// `https://example.com/akia_page`、`task-1` 之类整条打码。
fn secret_markers() -> Array[String] {
  [
    "bearer ", "sk-", "ghp_", "gho_", "ghs_", "github_pat_", "akia", "xoxb-", "xoxp-",
  ]
}

///|
fn is_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_upper(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_letter(c : Char) -> Bool {
  is_lower(c) || is_upper(c)
}

///|
/// `s` 从 `at` 开始连续满足 `pred` 的字符数。
fn run_len(s : Array[Char], at : Int32, pred : (Char) -> Bool) -> Int32 {
  let mut n = 0
  while at + n < s.length() {
    let c = s[at + n]
    if !pred(c) {
      break
    }
    n = n + 1
  }
  n
}

///|
/// 关键词前缀之后允许的分隔符：`password`、`password=`、`password:`
/// 都算；`passwordless` 不算。值以引号开头时（`"password": "..."`、
/// `password='...'`）也认。
fn is_key_separator(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '=' ||
  c == ':' ||
  c == '"' ||
  c == '\'' ||
  c == '\\'
}

///|
/// `s[at..]` 是否像一段真正的密钥载荷：跳过开头的引号 / 等号后至少有
/// `min` 个非空白字符。`task-1`、`bearer test` 这种自然语言会被排除。
fn looks_like_payload(s : Array[Char], at : Int32, min : Int32) -> Bool {
  let mut pos = at
  while pos < s.length() {
    let c = s[pos]
    if c == '"' || c == '\'' || c == '=' || c == ':' || c == ' ' || c == '\t' {
      pos = pos + 1
    } else {
      break
    }
  }
  let mut n = 0
  while pos + n < s.length() {
    let c = s[pos + n]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '"' || c == '\'' {
      break
    }
    n = n + 1
  }
  n >= min
}

///|
/// 在 `at` 处检查一种裸密钥前缀，命中时返回 `true`。
///
/// 除前缀本身外还要求：
/// - 前缀前面不是字母或数字（`zhakia` 不算，`e.g. sk-...` 中空格后的 `sk-` 算）；
/// - 前缀后面是“更像密钥”的字符序列，而不是普通单词。
fn match_secret_marker(s : Array[Char], at : Int32, marker : String) -> Bool {
  if at > 0 {
    let prev = s[at - 1]
    if is_letter(prev) || is_digit(prev) {
      return false
    }
  }
  let after = at + marker.length()
  if marker == "bearer " {
    let t = at + 7
    if t >= s.length() {
      return false
    }
    let body = run_len(s, t, fn(c) {
      is_letter(c) || is_digit(c) || c == '_' || c == '-'
    })
    return body >= 20
  }
  if marker == "sk-" {
    // `sk-ant-...` / `sk-proj-...` 是一长串，`task-1`、`risk-free` 不是
    return looks_like_payload(s, after, 12)
  }
  if marker == "akia" {
    // AWS Access Key ID：`AKIA` + 16 位大写字母 / 数字
    let body = run_len(s, after, fn(c) { is_upper(c) || is_digit(c) })
    return body >= 16
  }
  if marker == "ghp_" ||
    marker == "gho_" ||
    marker == "ghs_" ||
    marker == "github_pat_" {
    return run_len(s, after, fn(c) { is_letter(c) || is_digit(c) }) >= 20
  }
  if marker == "xoxb-" || marker == "xoxp-" {
    // `xoxb-1234-5678-abcd`：前缀后一直到空白 / 引号为止，
    // 至少包含两段由 `-` 连接的字母数字
    let mut pos = after
    let mut segments = 0
    while pos < s.length() {
      let c = s[pos]
      if is_letter(c) || is_digit(c) {
        pos = pos + 1
        continue
      }
      let prev = s[pos - 1]
      if c == '-' && (is_letter(prev) || is_digit(prev)) {
        segments = segments + 1
        pos = pos + 1
        continue
      }
      break
    }
    return segments >= 2
  }

  false
}

///|
/// 文本里是否含有裸密钥前缀。匹配位置之外的部分不看，误判面比
/// “整段小写后找子串”小得多。
fn has_secret_token(text : String) -> Bool {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  // 按值拷贝成 `Array[Char]`：直接用 `String` 的下标会得到 UTF-16 码元
  let markers : Array[Array[Char]] = secret_markers().map(fn(m) {
    let out : Array[Char] = []
    for c in m {
      out.push(c)
    }
    out
  })
  for i in 0..<chars.length() {
    if i > 0 && (is_letter(chars[i - 1]) || is_digit(chars[i - 1])) {
      continue
    }
    for marker in markers {
      if i + marker.length() > chars.length() {
        continue
      }
      // 逐个字符小写化后比较
      let mut same = true
      for k in 0..<marker.length() {
        let c = chars[i + k]
        let lower = if is_upper(c) {
          Int32::unsafe_to_char(c.to_int() + 32)
        } else {
          c
        }
        if lower != marker[k] {
          same = false
          break
        }
      }
      let prefix = StringBuilder()
      for c in marker {
        prefix.write_char(c)
      }
      if same && match_secret_marker(chars, i, prefix.to_string()) {
        return true
      }
    }
  }
  false
}

///|
/// 敏感关键词（`password`、`token` …）后面必须跟分隔符，不能是单词的一部分。
fn contains_keyword(s : String, keywords : Array[String]) -> Bool {
  let chars : Array[Char] = []
  for c in lower_ascii(s) {
    chars.push(c)
  }
  keywords.any(fn(k) {
    let needle : Array[Char] = []
    for c in k {
      needle.push(c)
    }
    let mut at = 0
    while at + needle.length() <= chars.length() {
      let mut same = true
      let mut i = 0
      while i < needle.length() {
        if chars[at + i] != needle[i] {
          same = false
          break
        }
        i = i + 1
      }
      if same {
        let after = at + needle.length()
        if after == chars.length() {
          return true
        }
        let next = chars[after]
        if is_key_separator(next) {
          return true
        }
      }
      at = at + 1
    }
    false
  })
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
  if has_secret_token(trimmed.to_owned()) ||
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
        // 键名按单词匹配：`task=` 里的 `sk` 不算敏感键
        if contains_keyword(trimmed[:eq].to_owned(), words) {
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
  if last.contains("=") && contains_keyword(last.to_owned(), words) {
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
