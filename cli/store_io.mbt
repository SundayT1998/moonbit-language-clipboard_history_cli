///|
/// 历史文件所在目录：优先 `MTUCK_DIR`，否则 `$HOME/.local/share/mtuck`。
pub fn data_dir() -> String {
  let custom = @env.get_env_var("MTUCK_DIR")
  if custom is Some(dir) && dir != "" {
    return absolute(dir)
  }
  match @env.get_env_var("HOME") {
    Some(home) =>
      if home != "" {
        "\{home}/.local/share/mtuck"
      } else {
        fallback_dir()
      }
    None => fallback_dir()
  }
}

///|
/// 没有 `HOME` 时的兜底目录 `.mtuck`。补成绝对路径：相对路径要相对于
/// **当前工作目录**算，`watch` 跑着的时候切换目录也不会写到别处去。
fn fallback_dir() -> String {
  absolute(".mtuck")
}

///|
fn absolute(path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    match @env.current_dir() {
      Some(cwd) => "\{cwd}/\{path}"
      None => path
    }
  }
}

///|
fn history_path() -> String {
  "\{data_dir()}/history.tsv"
}

///|
/// 读历史；文件还不存在（首次运行）就返回空历史。
async fn load() -> @history.History {
  load_from(history_path())
}

///|
/// 写历史。先写 `.tmp` 再 rename，Ctrl-C 打断也不会留下半个文件。
///
/// 失败时错误已经打到 stderr，返回 `false` 让命令层把退出码改成 1：
/// 脚本 / CI 必须能感知到“历史没写进去”。
async fn save(history : @history.History) -> Bool {
  save_to(history, history_path(), data_dir())
}

///|
/// 把历史写进给定的 `path`（目录 `dir` 会被创建并收紧到 0700）。
///
/// 路径显式传进来而不是内部读环境变量，测试才能在不改进程环境的前提下
/// 把文件写进临时目录。成功返回 `true`。
async fn save_to(
  history : @history.History,
  path : String,
  dir : String,
) -> Bool {
  let tmp = "\{path}.tmp"
  // 历史文件里有密码和 token 原文：目录 0700、文件 0600，只给当前用户读。
  @fs.mkdir(dir, permission=0o700, recursive=true, allow_existing=true) catch {
    _ => ()
  }
  // 收紧已存在目录的权限（老版本建出来的可能是 0755）
  @fs.chmod(dir, 0o700) catch {
    _ => ()
  }
  @fs.write_text(
    tmp,
    @history.encode(history),
    permission=0o600,
    create_mode=CreateOrTruncate,
  ) catch {
    e => {
      eprintln("mtuck: 写历史失败: \{e}")
      return false
    }
  }
  // `permission` 只对新建文件生效，tmp 可能来自更早的版本；rename 之前再收一次
  @fs.chmod(tmp, 0o600) catch {
    _ => ()
  }
  @fs.rename(tmp, path, replace=true) catch {
    e => {
      eprintln("mtuck: 保存历史失败: \{e}")
      return false
    }
  }
  true
}

///|
/// 从给定路径读历史；文件不存在或读不出来都当成空历史。
async fn load_from(path : String) -> @history.History {
  let exists = @fs.exists(path) catch { _ => false }
  if !exists {
    return @history.History::new()
  }
  let raw = @fs.read_text(path) catch { _ => "" }
  @history.decode(raw)
}

///|
/// 读-改-写三步的快捷封装。写失败返回 `Err(message)`。
async fn with_history(
  action : async (@history.History) -> Unit,
) -> Result[Unit, String] {
  let history = load()
  action(history)
  if save(history) {
    Ok(())
  } else {
    Err("历史没有写入磁盘")
  }
}
