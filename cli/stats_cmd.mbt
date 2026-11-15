///|
/// `stats` 的统计结果。字符数与 UTF-8 字节数口径不同：单条上限按字节算，
/// 所以两个都报。
pub struct Stats {
  total : Int32
  pinned : Int32
  secrets : Int32
  chars : Int32
  bytes : Int32
  kinds : Map[String, Int32]
}

///|
/// 遍历历史，算条目规模与类型分布。
fn compute_stats(history : @history.History) -> Stats {
  let mut pinned = 0
  let mut secrets = 0
  let mut chars = 0
  let mut bytes = 0
  let kinds : Map[String, Int32] = Map([])
  for e in history.entries {
    if e.pinned {
      pinned = pinned + 1
    }
    if e.is_secret {
      secrets = secrets + 1
    }
    chars = chars + e.text.length()
    bytes = bytes + @utf8.encode(e.text).length()
    let count = kinds.get(e.kind_label).unwrap_or(0)
    kinds[e.kind_label] = count + 1
  }
  { total: history.len(), pinned, secrets, chars, bytes, kinds, }
}

///|
async fn command_stats(args : Args, path~ : String = history_path()) -> Int32 {
  let history = load_from(path)
  let stats = compute_stats(history)
  if args.json {
    print_json_stats(stats, path)
    return 0
  }
  println("条目     \{stats.total} / \{@history.max_entries}")
  println("已固定   \{stats.pinned}")
  println("疑似密钥 \{stats.secrets}")
  println("总字符   \{stats.chars}")
  println("总字节   \{stats.bytes}")
  println("存储     \{path}")
  if !stats.kinds.is_empty() {
    let pairs = stats.kinds.to_array()
    pairs.sort_by(fn(a, b) { b.1.compare(a.1) })
    let line = pairs.map(fn(p) { "\{p.0}×\{p.1}" }).join("  ")
    println("类型分布 \{line}")
  }
  0
}
