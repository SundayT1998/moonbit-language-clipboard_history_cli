///|
/// 应用 `-p` / `-q` 过滤，返回命中条目。不做 `-n` 截断。
fn matched(history : @history.History, args : Args) -> Array[Int32] {
  let out = []
  for i, e in history.entries {
    if args.pinned_only && !e.pinned {
      continue
    }
    match args.query {
      Some(q) => if !e.text.contains(q) { continue }
      None => ()
    }
    out.push(i)
  }
  out
}

///|
/// 统一应用 `-p` / `-q` 过滤和 `-n` 截断，返回 `(要展示的下标, 过滤后总数)`。
/// 总数给底部统计区分“匹配数”和“展示数”用，不必把过滤再跑一遍。
fn select_with_count(
  history : @history.History,
  args : Args,
) -> (Array[Int32], Int32) {
  let indexes = matched(history, args)
  let total = indexes.length()
  let shown = if args.limit > 0 && total > args.limit {
    indexes[:args.limit].to_owned()
  } else {
    indexes
  }
  (shown, total)
}

///|
/// 单条预览：`-f` 原样显示，密钥始终打码，其余折成一行并截断。
fn entry_preview(e : @history.Entry, full : Bool) -> String {
  if full {
    e.text
  } else if e.is_secret {
    @history.mask(@history.summary(e.text, 24))
  } else {
    @history.summary(e.text, 60)
  }
}

///|
/// `list` 底部统计里的一条提示。`None` 表示没什么可说的（没有截断）。
///
/// 区分“匹配数”和“展示数”：过滤后的条目被 `-n` 截断时，
/// 只报过滤前的总数会让读者误以为命中了很多 / 很少。
fn list_footer(total : Int32, matched_count : Int32, shown : Int32) -> String? {
  if shown >= matched_count {
    return None
  }
  if matched_count == total {
    Some("（共 \{total} 条，只显示前 \{shown} 条；-n 0 看全部）")
  } else {
    Some(
      "（匹配 \{matched_count} 条，只显示前 \{shown} 条；-n 0 看全部）",
    )
  }
}

///|
/// 过滤后没有结果时的提示，区分“历史为空”“过滤条件太严”两种情况。
fn empty_list_hint(
  total : Int32,
  pinned_only : Bool,
  query : String?,
) -> String {
  if total == 0 {
    return "历史为空。先跑 `mtuck watch` 开始记录。"
  }
  let scope = if pinned_only { "固定条目" } else { "条目" }
  match query {
    Some(q) =>
      "没有匹配“\{q}”的\{scope}（共 \{total} 条历史）。"
    None => "没有\{scope}（共 \{total} 条历史）。"
  }
}

///|
async fn command_list(args : Args, path~ : String = history_path()) -> Int32 {
  let history = load_from(path)
  history.reclassify()
  let (indexes, matched_count) = select_with_count(history, args)
  if args.json {
    print_json_entries(history, indexes, full=args.full)
    return 0
  }
  if indexes.is_empty() {
    println(empty_list_hint(history.len(), args.pinned_only, args.query))
    return 0
  }
  let now = now_ms()
  for idx in indexes {
    match history.get(idx) {
      None => ()
      Some(e) => {
        let pin = if e.pinned { "★" } else { " " }
        println(
          "\{pin} #\{idx}  \{format_ago(e.ts, now)}  ×\{e.hits}  [\{e.kind_label}]  \{entry_preview(e, args.full)}",
        )
      }
    }
  }
  match list_footer(history.len(), matched_count, indexes.length()) {
    Some(line) => println(line)
    None => ()
  }
  0
}
