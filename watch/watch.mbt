///|
/// 一次轮询的结果。
pub(all) enum Poll {
  /// 内容发生变化
  Changed(String)
  /// 没变化，或读到空内容
  Idle
  /// 后端报错，交给调用方决定是否打印
  Failed(String)
}

///|
pub impl Eq for Poll with fn equal(self, other) {
  match (self, other) {
    (Changed(a), Changed(b)) => a == b
    (Idle, Idle) => true
    (Failed(a), Failed(b)) => a == b
    _ => false
  }
}

///|
pub impl Debug for Poll with fn to_repr(self) {
  match self {
    Changed(text) => Repr::string("Changed(\{text})")
    Idle => Repr::string("Idle")
    Failed(msg) => Repr::string("Failed(\{msg})")
  }
}

///|
pub extend Poll with Eq::{equal, not_equal}

///|
pub extend Poll with @debug.Debug::{to_repr}

///|
/// 剪贴板轮询器。`read` 是抽象出来的读取动作，测试里可以塞假实现，
/// 上层不必碰真实的系统剪贴板。
pub(all) struct Watcher {
  read : async () -> Result[String?, String]
  mut last_token : UInt64?
  mut last_text : String?
}

///|
pub fn Watcher::new(
  read : async () -> Result[String?, String],
  initial? : String?,
) -> Watcher {
  {
    read,
    last_token: @platform.change_token(),
    last_text: match initial {
      Some(Some(text)) => Some(text.trim().to_owned())
      _ => None
    },
  }
}

///|
/// 轮询一次。只有文本真的变了才返回 `Changed`。
///
/// Linux 下 `xclip` 没有“值有没有变”的查询接口，只能读文本比对；
/// macOS 的 `NSPasteboard.changeCount`、Windows 的
/// `GetClipboardSequenceNumber` 是现成的轻量变更计数，省掉整段文本的读。
pub async fn Watcher::poll(self : Watcher) -> Poll {
  let token = @platform.change_token()
  if token is Some(t) && self.last_token is Some(prev) && t == prev {
    return Idle
  }
  self.last_token = token
  let text = try {
    let read = self.read
    read()
  } catch {
    e => return Failed(e.to_string())
  }
  match text {
    Err(msg) => Failed(msg)
    Ok(None) => Idle
    Ok(Some(t)) => {
      let norm = t.trim().to_owned()
      if norm.is_empty() || (self.last_text is Some(prev) && prev == norm) {
        Idle
      } else {
        self.last_text = Some(norm)
        Changed(norm)
      }
    }
  }
}

///|
/// 阻塞式监视循环：每 `interval_ms` 轮询一次，有变化就回调，回调返回
/// `false` 时退出。`on_error` 只在错误状态切换时触发一次，避免刷屏。
pub async fn watch_loop(
  watcher : Watcher,
  interval_ms : Int32,
  on_change : async (String) -> Bool,
  on_error~ : async (String) -> Unit = fn(_) { () },
) -> Unit {
  let mut last_error : String? = None
  while true {
    match watcher.poll() {
      Changed(text) => {
        last_error = None
        if !on_change(text) {
          break
        }
      }
      Idle => last_error = None
      Failed(msg) => {
        let repeated = match last_error {
          Some(prev) => prev == msg
          None => false
        }
        if !repeated {
          last_error = Some(msg)
          on_error(msg)
        }
      }
    }
    @async.sleep(interval_ms)
  }
}
