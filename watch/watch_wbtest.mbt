///|
/// 假读取器：按顺序吐出预设内容，吐完就一直返回 `None`。
fn fake_reader(values : Array[String?]) -> async () -> Result[String?, String] {
  let cursor = Ref(0)
  fn() {
    let i = cursor.val
    cursor.val = i + 1
    if i < values.length() {
      Ok(values[i])
    } else {
      Ok(None)
    }
  }
}

///|
async test "poll 只在内容变化时返回 Changed" {
  let read = fake_reader([Some("a"), Some("b")])
  let watcher = Watcher::new(read, initial=Some("a"))
  // 第一条 a 与初始值相同，不算变化
  assert_eq(watcher.poll(), Idle)
  assert_eq(watcher.poll(), Changed("b"))
  assert_eq(watcher.poll(), Idle)
}

///|
async test "poll 把空白与空读取当作 Idle" {
  let read = fake_reader([Some("   "), None])
  let watcher = Watcher::new(read)
  assert_eq(watcher.poll(), Idle)
  assert_eq(watcher.poll(), Idle)
}

///|
async test "poll 把后端错误转成 Failed" {
  let read : async () -> Result[String?, String] = fn() { Err("no backend") }
  let watcher = Watcher::new(read)
  assert_eq(watcher.poll(), Failed("no backend"))
}

///|
async test "poll 读失败后仍会刷新 last_token" {
  let mut failing = true
  let read : async () -> Result[String?, String] = fn() {
    if failing {
      Err("no clipboard")
    } else {
      Ok(Some("after"))
    }
  }
  let watcher = Watcher::new(read)
  assert_eq(watcher.poll(), Failed("no clipboard"))
  // 失败后 last_token 已被更新，下一轮即使后端不报错也能读到新内容
  failing = false
  assert_eq(watcher.poll(), Changed("after"))
  // 第二轮 token 与 last_token 相同，走 Idle 快速路径
  assert_eq(watcher.poll(), Idle)
}

///|
async test "watch_loop 连续读失败只回调一次错误，之后恢复正常" {
  let mut phase = 0 // 0: 一直失败，1: 正常
  let read : async () -> Result[String?, String] = fn() {
    if phase == 0 {
      Err("no clipboard")
    } else {
      Ok(Some("after"))
    }
  }
  let watcher = Watcher::new(read)
  let errors : Array[String] = []
  let mut changes = 0
  watch_loop(
    watcher,
    0,
    fn(_) {
      changes = changes + 1
      false
    },
    on_error=fn(msg) {
      errors.push(msg)
      phase = 1
    },
  )
  assert_eq(errors.length(), 1)
  assert_eq(errors[0], "no clipboard")
  assert_eq(changes, 1)
}
