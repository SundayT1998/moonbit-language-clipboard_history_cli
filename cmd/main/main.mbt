///|
/// `mtuck` —— 终端剪贴板历史。
///
/// 所有命令共享一句话的定位：把系统剪贴板当成可回溯的时间线。
async fn main {
  let args = @env.args()
  let code = run(args) catch {
    e => {
      eprintln("mtuck: \{e}")
      1
    }
  }
  @env.exit(code)
}

///|
async fn run(args : Array[String]) -> Int32 {
  let argv : Array[String] = if args.is_empty() {
    []
  } else {
    args[1:].to_owned()
  }
  let parsed = parse_args(argv)
  match parsed.command {
    "help" | "--help" | "-h" | "" => {
      print_help()
      0
    }
    "version" | "--version" => {
      println("mtuck 0.1.0")
      0
    }
    "watch" => command_watch(parsed)
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
