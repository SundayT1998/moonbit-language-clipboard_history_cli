///|
/// 解析后的命令行。
pub(all) struct Args {
  command : String
  /// 位置参数（如条目下标、搜索词）
  positional : Array[String]
  limit : Int32
  /// 显示完整内容，不截断、不打码
  full : Bool
  /// 只保留固定条目
  pinned_only : Bool
  /// 搜索词，`None` 表示不搜索
  query : String?
  json : Bool
}

///|
fn default_args(command : String) -> Args {
  {
    command,
    positional: [],
    limit: 20,
    full: false,
    pinned_only: false,
    query: None,
    json: false,
  }
}

///|
fn parse_args(argv : Array[String]) -> Result[Args, String] {
  let mut parsed = default_args(if argv.is_empty() { "" } else { argv[0] })
  let positional = []
  let mut i = if argv.is_empty() { 0 } else { 1 }
  while i < argv.length() {
    let arg = argv[i]
    if arg == "-n" || arg == "--limit" {
      if i + 1 >= argv.length() {
        return Err("mtuck: 选项 `\{arg}` 缺少取值")
      }
      let value = argv[i + 1]
      let limit = Some(@string.parse_int(value)) catch { _ => None }
      match limit {
        Some(k) if k >= 0 => parsed = { ..parsed, limit: k, }
        _ =>
          return Err("mtuck: `\{arg}` 需要非负整数，收到 `\{value}`")
      }
      i = i + 1
    } else if arg == "-f" || arg == "--full" {
      parsed = { ..parsed, full: true, }
    } else if arg == "-p" || arg == "--pinned" {
      parsed = { ..parsed, pinned_only: true, }
    } else if arg == "-q" || arg == "--query" {
      if i + 1 >= argv.length() {
        return Err("mtuck: 选项 `\{arg}` 缺少取值")
      }
      parsed = { ..parsed, query: Some(argv[i + 1]), }
      i = i + 1
    } else if arg == "--json" {
      parsed = { ..parsed, json: true, }
    } else if arg.has_prefix("-") && arg != "-" {
      eprintln("忽略未知选项 `\{arg}`")
    } else {
      positional.push(arg)
    }
    i = i + 1
  }
  Ok({ ..parsed, positional, })
}

///|
fn print_help() -> Unit {
  let text =
    #|mtuck —— 终端剪贴板历史
    #|
    #|用法: mtuck <命令> [选项]
    #|
    #|命令:
    #|  watch            持续监听剪贴板，把每次复制写进历史（Ctrl-C 退出）
    #|  list, ls         列出历史条目
    #|  show <n>         打印第 n 条的完整内容
    #|  copy, cp <n>     把第 n 条写回系统剪贴板
    #|  pin <n>          固定第 n 条（不被上限淘汰，不参与去重合并）
    #|  unpin <n>        取消固定
    #|  rm <n>           删除第 n 条
    #|  clear            清空历史（默认保留固定条目）
    #|  stats            看看历史规模
    #|
    #|选项:
    #|  -n, --limit <k>  list 最多显示 k 条（默认 20，0 表示全部）
    #|  -f, --full       显示完整内容，不打码不截断 (--json 输出同样生效)
    #|  -p, --pinned     只显示固定条目
    #|  -q, --query <s>  按子串过滤
    #|      --json       以 JSON 数组输出
    #|
    #|环境变量:
    #|  MTUCK_DIR   历史文件所在目录（默认 ~/.local/share/mtuck）
  println(text)
}
