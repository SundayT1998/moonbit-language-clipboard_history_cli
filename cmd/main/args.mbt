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
  /// 原始参数（不含程序名），按命令校验选项时要用
  argv : Array[String]
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
    argv: [],
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
  let mut parsed = {
    ..default_args(if argv.is_empty() { "" } else { argv[0] }),
    argv: argv[:].to_owned(),
  }
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
        // 与缺值 / 取值非法一样按用法错误处理：拼错的选项要在脚本里被发现
        return Err(
          "mtuck: 未知选项 `\{arg}`（`--` 之后的内容按位置参数处理）",
        )
      } else {
        positional.push(arg)
      }
    }
    i = i + 1
  }
  let parsed = { ..parsed, positional, }
  match check_options(parsed) {
    Ok(_) => Ok(parsed)
    Err(msg) => Err(msg)
  }
}

///|
/// 每个命令允许的选项。`None` 表示不限（help / 未知命令交给 `dispatch`）。
fn allowed_options(command : String) -> Array[String]? {
  match command {
    "list" | "ls" =>
      Some([
        "-n", "--limit", "-f", "--full", "-p", "--pinned", "-q", "--query", "--json",
      ])
    "show" =>
      // show 的 `-f` 决定是否显示密钥原文
      Some(["-f", "--full"])
    "copy" | "cp" | "pin" | "unpin" | "rm" | "remove" => Some([])
    // clear 的 `-f` 表示连固定条目一起删
    "clear" => Some(["-f", "--full"])
    "watch" => Some(["-i", "--interval"])
    "stats" => Some(["--json"])
    _ => None
  }
}

///|
/// 选项名（`--limit=5` 这种内联写法取等号前的部分）。
fn option_name(arg : String) -> String {
  match arg.find("=") {
    Some(eq) if arg.has_prefix("--") => arg[:eq].to_owned()
    _ => arg
  }
}

///|
/// 命令行里实际出现过的选项名（到 `--` 为止）。
fn option_names(argv : Array[String]) -> Array[String] {
  let names = []
  for arg in argv {
    if arg == "--" {
      break
    }
    if arg.length() > 1 && arg.has_prefix("-") {
      names.push(option_name(arg))
    }
  }
  names
}

///|
/// 按命令校验选项：解析是全局的，这里才把不在该命令允许列表里的选项
/// 拦下来。以前 `mtuck watch -q foo`、`mtuck clear --json` 会被静默忽略，
/// 看上去像是生效了。
fn check_options(args : Args) -> Result[Unit, String] {
  let allowed = match allowed_options(args.command) {
    Some(list) => list
    None => return Ok(())
  }
  for name in option_names(args.argv) {
    if !allowed.contains(name) {
      let usage = if allowed.is_empty() {
        "不接受选项"
      } else {
        "只支持 \{allowed.join(", ")}"
      }
      return Err("mtuck: `\{args.command}` \{usage}，收到 `\{name}`")
    }
  }
  Ok(())
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
