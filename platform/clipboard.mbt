///|
/// 读 / 写剪贴板的原生入口。
///
/// 这一层只做 FFI 与错误码翻译，不判断“该不该用”：能不能用、为什么不能用、
/// 该给用户看什么话，由 `backend.mbt` 里的探测逻辑决定，那样才能喂假的
/// `PATH` / `DISPLAY` 覆盖各种失败分支。

///|
/// 原生实现的错误码，与 `clipboard_backend.c` 文件头的约定一一对应。
priv enum ClipRc {
  RcOk = 0
  ReadFailed = 1
  WriteFailed = 2
  NoBackend = 3
  NoDisplay = 4
}

///|
fn ClipRc::from_int(code : Int32) -> ClipRc {
  match code {
    0 => RcOk
    1 => ReadFailed
    2 => WriteFailed
    3 => NoBackend
    4 => NoDisplay
    // C 侧以后加新错误码时当作读写失败，不至于把失败误报成成功
    _ => ReadFailed
  }
}

///|
/// 读剪贴板文本。成功但内容为空返回 `Ok(None)`。
pub fn read_text() -> Result[String?, String] noraise {
  // 先拿到一个 8 字节的空盒，C 侧把文本指针写在里面；返回值留给结果码
  let slot = Bytes::make(8, b'\x00')
  let code = read_raw(slot)
  if @env.get_env_var("MTUCK_DEBUG") is Some(_) {
    // 临时排查用，提交前删掉
    println("debug: rc=\{code} slot=\{slot}")
  }
  let payload = payload_from_slot(slot)
  match ClipRc::from_int(code) {
    RcOk =>
      if payload.length() == 0 {
        Ok(None)
      } else {
        Ok(Some(@utf8.decode_lossy(payload[:])))
      }
    ReadFailed =>
      Err(
        "剪贴板里没有可读取的文本（可能存着图片或超长内容）",
      )
    WriteFailed => Err("剪贴板读取失败")
    NoBackend => Err("没有可用的剪贴板后端")
    NoDisplay => Err("连不上图形服务器，剪贴板不可用")
  }
}

///|
/// 写剪贴板文本，失败时返回人话原因。
pub fn write_text(text : String) -> Result[Unit, String] noraise {
  match clip_error(write_raw(@utf8.encode(text))) {
    None => Ok(())
    Some(msg) => Err(msg)
  }
}

///|
/// 系统原生剪贴板 API 的名字：Windows 是 `Windows`，macOS 是 `AppKit`，
/// 走命令行后端的平台是空串。
pub fn native_kind() -> String {
  @utf8.decode_lossy(native_kind_raw()[:])
}

///|
/// 错误码转成人话。`None` 表示成功。
fn clip_error(code : Int32) -> String? {
  match ClipRc::from_int(code) {
    RcOk => None
    ReadFailed | WriteFailed => Some("剪贴板操作失败")
    NoBackend => Some("没有可用的剪贴板后端")
    NoDisplay => Some("连不上图形服务器，剪贴板不可用")
  }
}

///|
/// 读出 `slot` 里那 8 个字节，并按指针取回文本字节。
///
/// FFI 的返回值只能有一个，而读剪贴板既要文本又要错误码，所以把文本指针
/// 写进出参 `slot`（C 侧约定的 8 字节），结果码走返回值。
fn payload_from_slot(slot : Bytes) -> Bytes {
  // C 侧对失败会写回空数组，所以这里不需要再判全 0
  slot_to_payload(slot)
}

///|
/// 指针转字节数组这一步交给 C：MoonBit 侧拿不到那 8 个字节里的地址。
#borrow(slot)
extern "C" fn slot_to_payload(slot : Bytes) -> Bytes = "mtuck_clipboard_slot_bytes"

///|
/// 文本通过出参 `slot` 带回，返回值留给结果码。
#borrow(slot)
extern "C" fn read_raw(slot : Bytes) -> Int32 = "mtuck_clipboard_read"

///|
#borrow(text)
extern "C" fn write_raw(text : Bytes) -> Int32 = "mtuck_clipboard_write"

///|
extern "C" fn native_kind_raw() -> Bytes = "mtuck_clipboard_native_kind"

///|
/// 平台名：`windows` / `macos` / `linux` / `unknown`。
pub fn os_name() -> String {
  @utf8.decode_lossy(os_name_raw()[:])
}

///|
extern "C" fn os_name_raw() -> Bytes = "mtuck_os_name"

///|
/// 路径是否存在。`DISPLAY` 指向的 socket、`PATH` 里的命令都用它判定。
pub fn path_exists(path : String) -> Bool {
  path_exists_raw(@utf8.encode(path)) == 1
}

///|
#borrow(path)
extern "C" fn path_exists_raw(path : Bytes) -> Int32 = "mtuck_path_exists"
