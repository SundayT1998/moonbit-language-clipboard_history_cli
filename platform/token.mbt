///|
/// 平台剪贴板变更计数：macOS 走 `NSPasteboard.changeCount`，Windows 走
/// `GetClipboardSequenceNumber`，其他平台（含 Linux 的 xclip）返回 `None`，
/// 调用方退化成读文本比对。
pub fn change_token() -> UInt64? {
  let token = token_raw()
  if token == 0 {
    None
  } else {
    Some(token)
  }
}

///|
/// 见 `stub.c`：拿不到原生接口时返回 0。
extern "C" fn token_raw() -> UInt64 = "hk_clipboard_change_token"
