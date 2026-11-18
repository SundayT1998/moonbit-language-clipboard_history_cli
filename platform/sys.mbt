///|
/// 把真实的系统状态读成 `Env`：平台名、原生 API、`PATH` 里有哪些命令、
/// 显示服务器的地址与 socket。判定留在 `detect` 里，这里只负责采集。

///|
/// `PATH` 里的所有目录。分隔符 Windows 是 `;`，其他平台是 `:`。
pub fn path_dirs(path : String) -> Array[String] {
  let separator = if os_name() == "windows" { ";" } else { ":" }
  let dirs : Array[String] = []
  for dir in path.split(separator) {
    let trimmed = dir.to_owned()
    if !trimmed.is_empty() {
      dirs.push(trimmed)
    }
  }
  dirs
}

///|
/// 相对目录靠 `PATH` 本身没有意义，这里只认绝对路径，
/// 免得把当前目录里恰好同名的可执行文件当成后端。
pub fn is_command_in(dirs : Array[String], name : String) -> Bool {
  let file = if os_name() == "windows" { "\{name}.exe" } else { name }
  for dir in dirs {
    if path_exists("\{dir}/\{file}") {
      return true
    }
  }
  false
}

///|
/// `DISPLAY` 指向的 X server 还在不在。
pub fn x11_socket_alive(display : String) -> Bool {
  for path in socket_path_candidates(display) {
    if path_exists(path) {
      return true
    }
  }
  false
}

///|
/// `WAYLAND_DISPLAY` 可能是相对 `XDG_RUNTIME_DIR` 的名字，也可能是绝对路径。
pub fn wayland_socket_paths(name : String) -> Array[String] {
  if name.has_prefix("/") {
    return [name]
  }
  match @env.get_env_var("XDG_RUNTIME_DIR") {
    Some(dir) if dir != "" => ["\{dir}/\{name}"]
    _ => []
  }
}

///|
/// 采集当前进程的环境快照。
pub fn current_env() -> Env {
  let dirs = match @env.get_env_var("PATH") {
    Some(path) => path_dirs(path)
    None => []
  }
  // 会话变量来自环境，socket 来自文件系统；两者都只是事实，判断留给 `detect`
  let native = native_kind()
  let x11 = @env.get_env_var("DISPLAY").filter(fn(d) { d != "" })
  let wayland = @env.get_env_var("WAYLAND_DISPLAY").filter(fn(d) { d != "" })
  Env::{
    platform: os_name(),
    native,
    has_command: fn(name) { is_command_in(dirs, name) },
    x11_display: x11,
    wayland_display: wayland,
    has_socket: fn(name) {
      if x11 is Some(display) && display == name {
        x11_socket_alive(name)
      } else if wayland is Some(w) && w == name {
        let paths = wayland_socket_paths(name)
        paths.iter().any(fn(path) { path_exists(path) })
      } else {
        false
      }
    },
  }
}

///|
/// 当前环境的剪贴板可用性。
pub fn availability() -> Availability {
  detect(current_env())
}
