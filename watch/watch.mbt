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
  /// 上一次读取的失败信息，用于错误去重
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
/// 无论读取成功与否都会刷新 `last_token`：后端有变更计数时，失败的那一次
/// 不会被无限重试，`watch_loop` 的错误去重才能生效。
///
/// Linux 下（不论后端是 `wl-paste`、`xclip` 还是 `xsel`）都没有“值有没有变”的
/// 查询接口，只能读文本比对；macOS 的 `NSPasteboard.changeCount`、Windows 的
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
    e => Err(e.to_string())
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
  // 错误去重状态：反复读到同样的失败只报一次。
  let mut reported : String? = None
  while true {
    match watcher.poll() {
      Changed(text) => {
        reported = None
        if !on_change(text) {
          break
        }
      }
      Idle => reported = None
      Failed(msg) => {
        let repeated = match reported {
          Some(prev) => prev == msg
          None => false
        }
        if !repeated {
          reported = Some(msg)
          on_error(msg)
        }
      }
    }
    @async.sleep(interval_ms)
  }
}
