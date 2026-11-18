///|
/// 造一个环境快照：`commands` 里的命令在 `PATH` 里，`alive` 里的 socket 存在。
fn env(
  platform~ : String = "linux",
  native~ : String = "",
  commands~ : Array[String] = [],
  x11~ : String? = None,
  wayland~ : String? = None,
  alive~ : Array[String] = [],
) -> Env {
  Env::{
    platform,
    native,
    has_command: fn(name) { commands.contains(name) },
    x11_display: x11,
    wayland_display: wayland,
    has_socket: fn(name) { alive.contains(name) },
  }
}

///|
test "原生 API 优先：Windows / macOS 不需要外部命令" {
  let win = detect(env(platform="windows", native="Windows"))
  assert_true(win is Ready(Native("Windows")))
  let mac = detect(env(platform="macos", native="AppKit", commands=["xclip"]))
  assert_true(mac is Ready(Native("AppKit")))
}

///|
test "Wayland 会话优先选 wl-clipboard" {
  let result = detect(
    env(commands=["wl-paste", "wl-copy", "xclip"], wayland=Some("wayland-0"), alive=[
      "wayland-0",
    ]),
  )
  assert_true(result is Ready(Wayland))
}

///|
test "Wayland 会话但只有 xclip：借 XWayland 顶上" {
  let result = detect(
    env(commands=["xclip"], wayland=Some("wayland-0"), alive=["wayland-0"]),
  )
  assert_true(result is Ready(Xclip))
}

///|
test "X11 会话按 xclip → xsel 的顺序挑" {
  let both = detect(
    env(commands=["xclip", "xsel"], x11=Some(":0"), alive=[":0"]),
  )
  assert_true(both is Ready(Xclip))
  let only_xsel = detect(env(commands=["xsel"], x11=Some(":0"), alive=[":0"]))
  assert_true(only_xsel is Ready(Xsel))
}

///|
test "没有图形会话时报缺工具，而不是报没有显示服务器" {
  // 没装工具：先说缺工具，用户照着装就完了
  let bare = detect(env())
  assert_true(bare is Unavailable(MissingTools(_)))
  // 装了工具却没会话：说明环境本身就不是桌面
  let has_tools = detect(env(commands=["xclip"]))
  assert_true(has_tools is Unavailable(NoDisplay))
}

///|
test "有会话但缺工具：只报缺工具" {
  let result = detect(env(x11=Some(":0"), alive=[":0"]))
  assert_true(result is Unavailable(MissingTools(_)))
}

///|
test "显示地址设了但 socket 不在：报连不上，不报缺工具" {
  // 这种情况下装工具也没用，得先让服务器活着
  let result = detect(env(commands=["xclip"], x11=Some(":42")))
  assert_true(result is Unavailable(DisplayUnreachable(_)))
}

///|
test "两个显示变量都设了但都连不上：两个都列出来" {
  let result = detect(
    env(
      commands=["wl-copy", "wl-paste"],
      x11=Some(":0"),
      wayland=Some("wayland-1"),
    ),
  )
  match result {
    Unavailable(DisplayUnreachable(detail)) => {
      assert_true(detail.contains("WAYLAND_DISPLAY"))
      assert_true(detail.contains("DISPLAY"))
    }
    other => fail("期望连不上，实际是 \{other}")
  }
}

///|
test "空字符串的 DISPLAY 当作没设" {
  let result = detect(env(commands=["xclip"], x11=Some("")))
  assert_true(result is Unavailable(NoDisplay))
}

///|
test "socket_path_candidates 只认本地 display" {
  assert_eq(socket_path_candidates(":0"), [
    "/tmp/.X11-unix/X0", "/tmp/.X11-unix/X0.lock",
  ])
  assert_eq(socket_path_candidates(":1.0"), [
    "/tmp/.X11-unix/X1", "/tmp/.X11-unix/X1.lock",
  ])
  // 走 TCP 的 display 没法通过 socket 文件判断，交给后端自己连
  assert_eq(socket_path_candidates("host:0"), [])
  assert_eq(socket_path_candidates(""), [])
  assert_eq(socket_path_candidates(":"), [])
}

///|
test "path_dirs 会丢掉空段" {
  assert_eq(path_dirs("/usr/bin::/bin:"), ["/usr/bin", "/bin"])
  assert_eq(path_dirs(""), [])
}
