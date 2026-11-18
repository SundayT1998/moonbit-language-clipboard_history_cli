///|
/// 剪贴板后端的可用性判定。
///
/// 这一层是纯逻辑：拿到的是一份“环境快照”（PATH 里有哪些命令、`DISPLAY` /
/// `WAYLAND_DISPLAY` 是什么、对应的 socket 在不在、有没有原生 API），
/// 便于在测试里构造各种残缺环境，而不用真的起 X server 或者装 `xclip`。
///
/// 之所以要自己判一遍：命令行后端只会在 exec 时才因为连不上服务器而失败，
/// 那时 `watch` 已经在循环里了，用户看到的是一行行「读剪贴板失败」。
/// 提前判掉就能给一句能照着修的话。

///|
/// 一个平台后端。
pub(all) enum Backend {
  /// Windows / macOS 的系统原生 API，不需要外部命令
  Native(String)
  /// Wayland 客户端：`wl-paste` / `wl-copy`
  Wayland
  /// X11 客户端：`xclip`
  Xclip
  /// X11 客户端：`xsel`
  Xsel
}

///|
pub impl Show for Backend with fn output(self, logger) {
  match self {
    Native(name) => logger.write_string("\{name}（系统原生 API）")
    Wayland => logger.write_string("wl-clipboard（wl-paste / wl-copy）")
    Xclip => logger.write_string("xclip")
    Xsel => logger.write_string("xsel")
  }
}

///|
/// 后端不可用的几种原因，每一种都对应一句能照着修的建议。
pub(all) enum BackendError {
  /// 需要图形会话，但进程跑在纯 SSH / CI / 无 X11 的容器里
  NoDisplay
  /// 有图形会话，但 `PATH` 里找不到对应的命令行工具
  MissingTools(String)
  /// 图形会话存在，但 socket 连不上（服务器已退出、`DISPLAY` 指错）
  DisplayUnreachable(String)
  /// 不认识的平台
  UnsupportedPlatform
}

///|
pub impl Show for BackendError with fn output(self, logger) {
  match self {
    NoDisplay =>
      logger.write_string(
        "当前没有图形会话（DISPLAY / WAYLAND_DISPLAY 都没设），剪贴板不可用；\n" +
        "mtuck 的 watch / copy 需要桌面会话、Xvfb 或 ssh -X 转发。\n" +
        "历史本身仍然可以读写：list / show / pin / rm / stats 不依赖剪贴板。",
      )
    MissingTools(tools) =>
      logger.write_string(
        "图形会话在，但没找到剪贴板工具：需要 \{tools} 之一。\n" +
        "装一个即可，例如 Debian/Ubuntu 用 `sudo apt install wl-clipboard` 或 `xclip`。",
      )
    DisplayUnreachable(detail) =>
      logger.write_string(
        "图形服务器的地址设了，但连不上：\{detail}。\n" +
        "常见原因是进程跑在别的 X server 里、Xvfb 已经退出，或者 ssh 忘了带 -X。",
      )
    UnsupportedPlatform =>
      logger.write_string(
        "这个平台没有可用的剪贴板后端；mtuck 支持 Windows、macOS 和带图形会话的 Linux。",
      )
  }
}

///|
/// 一次可用性探测的结果。
pub(all) enum Availability {
  Ready(Backend)
  Unavailable(BackendError)
}

///|
pub impl Show for Availability with fn output(self, logger) {
  match self {
    Ready(backend) => Show::output(backend, logger)
    Unavailable(error) => Show::output(error, logger)
  }
}

///|
/// 探测用的环境快照。字段都是“从系统里读到的原始事实”，不含判断。
pub(all) struct Env {
  /// 平台名，与 `@platform.@os` 的取名一致：`windows` / `macos` / `linux`
  platform : String
  /// 系统里有原生剪贴板 API 时的名字（Windows 为 `Windows`，macOS 为 `AppKit`）
  native : String
  /// `PATH` 里能找到的命令
  has_command : (String) -> Bool
  /// `DISPLAY` 的值
  x11_display : String?
  /// `WAYLAND_DISPLAY` 的值
  wayland_display : String?
  /// 指定的 socket 是否存在（`DISPLAY` 与 `WAYLAND_DISPLAY` 用同一套判定）
  has_socket : (String) -> Bool
}

///|
/// 判定的主入口。顺序即优先级：原生 → Wayland → X11。
pub fn detect(env : Env) -> Availability {
  if env.native != "" {
    return Ready(Native(env.native))
  }
  let can_wayland = (env.has_command)("wl-paste") &&
    (env.has_command)("wl-copy")
  let can_xclip = (env.has_command)("xclip")
  let can_xsel = (env.has_command)("xsel")
  // 先看图形会话：没有会话时“缺工具”是个误导性的结论
  let wayland_up = match env.wayland_display {
    None | Some("") => None
    Some(name) => if (env.has_socket)(name) { Some(true) } else { Some(false) }
  }
  let x11_up = match env.x11_display {
    None | Some("") => None
    Some(name) => if (env.has_socket)(name) { Some(true) } else { Some(false) }
  }
  match (wayland_up, x11_up) {
    (None, None) =>
      // 两个都没设：确实没有图形会话。但如果连工具都没装，先说缺工具更实用
      if !can_wayland && !can_xclip && !can_xsel {
        Unavailable(MissingTools("wl-clipboard、xclip 或 xsel"))
      } else {
        Unavailable(NoDisplay)
      }
    (Some(true), _) =>
      // Wayland 会话优先；wl-clipboard 不在时还能借 XWayland 用 xclip/xsel
      if can_wayland {
        Ready(Wayland)
      } else if can_xclip || can_xsel {
        Ready(if can_xclip { Xclip } else { Xsel })
      } else {
        Unavailable(
          MissingTools("wl-clipboard（Wayland 下推荐）或 xclip、xsel"),
        )
      }
    (_, Some(true)) =>
      if can_xclip || can_xsel {
        Ready(if can_xclip { Xclip } else { Xsel })
      } else if can_wayland {
        Ready(Wayland)
      } else {
        Unavailable(MissingTools("xclip 或 xsel"))
      }
    // 设了地址但 socket 不在：服务器没跑，或者 `DISPLAY` / `WAYLAND_DISPLAY` 指错
    (Some(false), Some(false)) | (Some(false), None) | (None, Some(false)) =>
      Unavailable(
        DisplayUnreachable(
          match (env.wayland_display, env.x11_display) {
            (Some(w), Some(d)) =>
              "WAYLAND_DISPLAY=\{w}、DISPLAY=\{d} 都没有对应 socket"
            (Some(w), None) => "WAYLAND_DISPLAY=\{w} 没有对应 socket"
            (None, Some(d)) => "DISPLAY=\{d} 没有对应 socket"
            (None, None) => "没有可用的显示服务器"
          },
        ),
      )
  }
}

///|
/// 探测显示会话是否真的可连：`DISPLAY=:0` 要能在 `/tmp/.X11-unix/X0` 找到 socket。
/// 没有 X11 的 `DISPLAY` 形态（比如 `host:0`）交给后端自己连，这里当作可达，
/// 不做多余的否定判断。
pub fn socket_path_candidates(display : String) -> Array[String] {
  // `:0`、`:0.0` 这类本地 display 才有 socket 文件；`host:0` 走 TCP，无从判断
  if !display.has_prefix(":") {
    return []
  }
  // `:0` / `:0.0` 取冒号后面、小数点前面那段
  let parts = display[1:].split(".").collect()
  let number : String = match parts {
    [] => ""
    [first, ..] => first.to_owned()
  }
  if number.is_empty() {
    return []
  }
  // 服务器的 socket 与锁文件；两者有一个在就认为服务器还活着
  ["/tmp/.X11-unix/X\{number}", "/tmp/.X11-unix/X\{number}.lock"]
}
