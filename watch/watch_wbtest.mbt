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
