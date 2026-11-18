///|
/// `mtuck` 的命令行入口，供 `cmd/main` 这样的 shell 调用。
///
/// 所有命令共享一句话的定位：把系统剪贴板当成可回溯的时间线。
/// 参数错误、未知命令返回 2，对应文档里“用法错误”的退出码。

///|
/// 执行一条命令并返回退出码。`args` 含程序名（`@env.args()` 的返回值），
/// 由 `cmd/main` 的 `main` 交给 `@env.exit`。
pub async fn run(args : Array[String]) -> Int32 {
  let code = run_inner(args) catch {
    e => {
      eprintln("mtuck: \{e}")
      1
    }
  }
  code
}

///|
/// `run` 去掉“捕获异常”那层，便于测试。`watch` 的剪贴板读取器同样可以注入，
/// 测试用它喂一段固定文本，从而覆盖 `run` → 分发 → `watch` → 落盘的整条链路。
pub async fn run_inner(
  args : Array[String],
  read_clip~ : async () -> Result[String?, String] = fn() { read_clipboard() },
) -> Int32 {
  let argv : Array[String] = if args.is_empty() {
    []
  } else {
    args[1:].to_owned()
  }
  let parsed = match parse_args(argv) {
    Ok(parsed) => parsed
    Err(msg) => {
      eprintln(msg)
      return 2
    }
  }
  dispatch(parsed, read_clip~)
}

///|
/// 按命令名分发。纯命令（help / version / 未知命令）可以脱离文件系统测试，
/// 其余命令各自读历史文件。
async fn dispatch(
  parsed : Args,
  read_clip~ : async () -> Result[String?, String],
) -> Int32 {
  match parsed.command {
    "help" | "--help" | "-h" | "" => {
      print_help()
      0
    }
    "version" | "--version" => {
      println("mtuck 0.1.0")
      0
    }
    "watch" => command_watch(parsed, read=read_clip)
    "list" | "ls" => command_list(parsed)
    "show" => command_show(parsed)
    "copy" | "cp" => command_copy(parsed)
    "pin" => command_pin(parsed, true)
    "unpin" => command_pin(parsed, false)
    "rm" | "remove" => command_remove(parsed)
    "clear" => command_clear(parsed)
    "stats" => command_stats(parsed)
    other => {
      eprintln("未知命令 `\{other}`，试 `mtuck help`")
      2
    }
  }
}
