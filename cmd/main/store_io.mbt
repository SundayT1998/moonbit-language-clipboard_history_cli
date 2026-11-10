///|
/// 历史文件所在目录：优先 `MTUCK_DIR`，否则 `$HOME/.local/share/mtuck`。
pub fn data_dir() -> String {
  let custom = @env.get_env_var("MTUCK_DIR")
  if custom is Some(dir) && dir != "" {
    return dir
  }
  match @env.get_env_var("HOME") {
    Some(home) =>
      if home != "" {
        "\{home}/.local/share/mtuck"
      } else {
        ".mtuck"
      }
    None => ".mtuck"
  }
}

///|
fn history_path() -> String {
  "\{data_dir()}/history.tsv"
}

///|
/// 读历史；文件还不存在（首次运行）就返回空历史。
pub async fn load() -> @history.History {
  let path = history_path()
  let exists = @fs.exists(path) catch { _ => false }
  if !exists {
    return @history.History::new()
  }
  let raw = @fs.read_text(path) catch { _ => "" }
  @history.decode(raw)
}

///|
/// 写历史。先写 `.tmp` 再 rename，Ctrl-C 打断也不会留下半个文件。
pub async fn save(history : @history.History) -> Unit {
  let dir = data_dir()
  let path = history_path()
  let tmp = "\{path}.tmp"
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    _ => ()
  }
  @fs.write_text(tmp, @history.encode(history)) catch {
    e => {
      eprintln("mtuck: 写历史失败: \{e}")
      return
    }
  }
  @fs.rename(tmp, path, replace=true) catch {
    e => eprintln("mtuck: 保存历史失败: \{e}")
  }
}

///|
/// 读-改-写三步的快捷封装。
pub async fn with_history(action : async (@history.History) -> Unit) -> Unit {
  let history = load()
  action(history)
  save(history)
}
