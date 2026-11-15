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
  /// `watch` 的轮询间隔（毫秒），`None` 用默认值；与 `-n`（列表条数）分开
  interval : Int32?
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
    interval: None,
  }
}

///|
fn parse_i32(s : String) -> Int32? {
  Some(@string.parse_int(s)) catch {
    _ => None
  }
}

///|
/// 取值占了几个 argv 位置：`-n 5` 占一个，`--limit=5` 不占。
fn value_step(inline : String?) -> Int32 {
  match inline {
    Some(_) => 0
    None => 1
  }
}

///|
fn parse_args(argv : Array[String]) -> Result[Args, String] {
  let mut parsed = default_args(if argv.is_empty() { "" } else { argv[0] })
  let positional = []
  let mut i = if argv.is_empty() { 0 } else { 1 }
  let mut only_positional = false
  while i < argv.length() {
    let arg = argv[i]
    if only_positional {
      positional.push(arg)
    } else if arg == "--" {
      // `--` 之后全部当下标，方便 `mtuck rm -- -1` 这种边界写法
      only_positional = true
    } else {
      let (name, inline) = match arg.find("=") {
        Some(eq) if arg.has_prefix("--") =>
          (arg[:eq].to_owned(), Some(arg[eq + 1:].to_owned()))
        _ => (arg, None)
      }
      // 取选项取值：支持 `-n 5` 与 `--limit=5` 两种写法
      let inline_v = inline
      let next_arg : String? = if i + 1 < argv.length() {
        Some(argv[i + 1])
      } else {
        None
      }
      let value_of = fn() -> String? {
        match inline_v {
          Some(v) => Some(v)
          None => next_arg
        }
      }
      if name == "-n" || name == "--limit" {
        let value = value_of()
        match value {
          Some(v) =>
            match parse_i32(v) {
              Some(k) if k >= 0 => parsed = { ..parsed, limit: k, }
              _ =>
                return Err(
                  "mtuck: `\{name}` 需要非负整数，收到 `\{v}`",
                )
            }
          None => return Err("mtuck: 选项 `\{name}` 缺少取值")
        }
        i = i + value_step(inline)
      } else if name == "--interval" || name == "-i" {
        let value = value_of()
        match value {
          Some(v) =>
            match parse_i32(v) {
              Some(k) if k > 0 && k <= 60_000 =>
                parsed = { ..parsed, interval: Some(k), }
              _ =>
                return Err(
                  "mtuck: `\{name}` 需要在 1..=60000 毫秒之间，收到 `\{v}`",
                )
            }
          None => return Err("mtuck: 选项 `\{name}` 缺少取值")
        }
        i = i + value_step(inline)
      } else if name == "-q" || name == "--query" {
        match value_of() {
          Some(v) => parsed = { ..parsed, query: Some(v), }
          None => return Err("mtuck: 选项 `\{name}` 缺少取值")
        }
        i = i + value_step(inline)
      } else if inline is Some(_) {
        return Err("mtuck: 选项 `\{name}` 不接受取值")
      } else if arg == "-f" || arg == "--full" {
        parsed = { ..parsed, full: true, }
      } else if arg == "-p" || arg == "--pinned" {
        parsed = { ..parsed, pinned_only: true, }
      } else if arg == "--json" {
        parsed = { ..parsed, json: true, }
      } else if arg.has_prefix("-") && arg != "-" {
        eprintln("忽略未知选项 `\{arg}`")
      } else {
        positional.push(arg)
      }
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
    #|  -i, --interval <ms>  watch 轮询间隔（默认 400ms）
    #|  -f, --full       显示完整内容，不打码不截断 (--json 输出同样生效)
    #|  -p, --pinned     只显示固定条目
    #|  -q, --query <s>  按子串过滤
    #|      --json       以 JSON 数组输出
    #|
    #|环境变量:
    #|  MTUCK_DIR   历史文件所在目录（默认 ~/.local/share/mtuck）
  println(text)
}
