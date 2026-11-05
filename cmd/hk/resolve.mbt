///|
/// 把命令行里的位置参数解析成条目下标。
///
/// - 不给参数 → 报错（`copy`/`show` 必须指明是哪一条）；
/// - `-1` / `last` / `latest` → 最新一条；
/// - `1,3,5` / `1-4` → 多个或区间，方便批量 `rm` / `pin`。
pub fn resolve_indexes(args : Args) -> Result[Array[Int32], String] {
  if args.positional.is_empty() {
    return Err("hk: 缺少条目编号（`hk list` 能看到编号）")
  }
  let out = []
  for token in args.positional {
    let t = token.to_lower()
    if t == "last" || t == "latest" || t == "-1" {
      out.push(0)
      continue
    }
    let dash = token.find("-")
    if dash is Some(pos) && pos > 0 {
      let parts = token.split("-").collect()
      if parts.length() == 2 {
        let lo = parse_index(parts[0])
        let hi = parse_index(parts[1])
        match (lo, hi) {
          (Some(a), Some(b)) if a <= b => {
            for i in a..<=b {
              out.push(i)
            }
            continue
          }
          _ => return Err("hk: 看不懂的下标区间 `\{token}`")
        }
      }
    }
    if token.contains(",") {
      for part in token.split(",") {
        match parse_index(part) {
          Some(i) => out.push(i)
          None => return Err("hk: 看不懂的下标 `\{part}`")
        }
      }
      continue
    }
    match parse_index(token) {
      Some(i) => out.push(i)
      None => return Err("hk: 看不懂的下标 `\{token}`")
    }
  }
  Ok(out)
}

///|
fn parse_index(token : StringView) -> Int32? {
  try {
    let n = @string.parse_int(token.trim())
    if n < 0 {
      None
    } else {
      Some(n)
    }
  } catch {
    _ => None
  }
}
