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
  // 启动时的内容也是新内容：watch 可能是在用户刚复制完之后才起来的
  let watcher = Watcher::new(read, initial=Some("a"))
  assert_eq(watcher.poll(), Changed("a"))
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

///|
async test "poll 的读取器抛异常时转成 Failed" {
  let read : async () -> Result[String?, String] = fn() raise {
    raise Failure("boom")
  }
  let watcher = Watcher::new(read)
  match watcher.poll() {
    Failed(msg) => assert_true(msg.contains("boom"))
    other => abort("预期 Failed，实际 \{Repr(other)}")
  }
}

///|
async test "poll 会把内容首尾空白去掉再比较" {
  let read = fake_reader([Some("  a  "), Some(" a"), Some("b ")])
  let watcher = Watcher::new(read)
  // 第一次读到的 a 是“新内容”，之后空白差异不算变化
  assert_eq(watcher.poll(), Changed("a"))
  assert_eq(watcher.poll(), Idle)
  assert_eq(watcher.poll(), Changed("b"))
}

///|
async test "没有变更计数时，启动瞬间的内容也会被记录" {
  // Linux 上没有 changeCount 这类接口，初始值不能直接当成“已经记过”：
  // 用户可能刚刚才复制，watch 还一次都没记
  let read = fake_reader([Some("刚复制的")])
  let watcher = Watcher::new(read, initial=Some("刚复制的"))
  assert_eq(watcher.poll(), Changed("刚复制的"))
}

///|
async test "有变更计数时，计数不变就不再去读剪贴板" {
  // macOS / Windows 上计数就是“变了没”的答案，连文本都不用读。
  let reads = Ref(0)
  let read : async () -> Result[String?, String] = fn() {
    reads.val = reads.val + 1
    Ok(Some("旧的"))
  }
  // 计数接口只在 macOS / Windows 上有，这里只在那些平台上验证
  if @platform.change_token() is Some(_) {
    let watcher = Watcher::new(read, initial=Some("旧的"))
    assert_eq(watcher.poll(), Idle)
    assert_eq(reads.val, 0)
  }
}

///|
async test "poll 在连续变化时每条都能被看到" {
  let read = fake_reader([Some("1"), Some("2"), Some("3"), Some("4")])
  let watcher = Watcher::new(read)
  let seen = []
  for _ in 0..<4 {
    seen.push(watcher.poll())
  }
  assert_eq(seen, [Changed("1"), Changed("2"), Changed("3"), Changed("4")])
}

///|
async test "watch_loop 在回调返回 false 时立刻退出" {
  let read = fake_reader([Some("1"), Some("2"), Some("3")])
  let watcher = Watcher::new(read)
  let seen = []
  watch_loop(watcher, 0, fn(text) {
    seen.push(text)
    seen.length() < 2
  })
  assert_eq(seen, ["1", "2"])
}

///|
async test "watch_loop 错误恢复后再次出错会重新上报" {
  // 序列：失败 → 成功 → 再次失败 → 回调退出
  let mut phase = 0
  let read : async () -> Result[String?, String] = fn() noraise {
    phase = phase + 1
    match phase {
      1 => Err("first")
      3 => Err("second")
      _ => Ok(Some("ok-\{phase}"))
    }
  }
  let watcher = Watcher::new(read)
  let errors = []
  let changes = []
  watch_loop(
    watcher,
    0,
    fn(text) {
      changes.push(text)
      false
    },
    on_error=fn(msg) { errors.push(msg) },
  )
  // 第一次错误上报；成功一次后错误状态被清掉，第二次错误会再报
  assert_eq(changes, ["ok-2"])
  assert_eq(errors.length(), 1)
  assert_eq(errors[0], "first")
}

///|
async test "watch_loop 期间连续失败只报一次同样的错误" {
  let mut calls = 0
  let read : async () -> Result[String?, String] = fn() {
    calls = calls + 1
    if calls >= 4 {
      Ok(Some("finally"))
    } else {
      Err("same")
    }
  }
  let watcher = Watcher::new(read)
  let errors = []
  watch_loop(watcher, 0, fn(_) { false }, on_error=fn(msg) { errors.push(msg) })
  assert_eq(errors, ["same"])
}

///|
async test "poll 对大小写与换行的变化敏感" {
  let read = fake_reader([Some("Hello"), Some("hello"), Some("hello\n")])
  let watcher = Watcher::new(read)
  assert_eq(watcher.poll(), Changed("Hello"))
  assert_eq(watcher.poll(), Changed("hello"))
  // 尾部换行被 trim 掉，与上一条相同
  assert_eq(watcher.poll(), Idle)
}

///|
test "Poll 的 Eq 与 Debug" {
  assert_eq(Changed("a"), Changed("a"))
  assert_true(Changed("a") != Changed("b"))
  assert_eq(Idle, Idle)
  assert_true(Changed("a") != Idle)
  assert_eq(Failed("x"), Failed("x"))
  assert_true(Idle != Failed("x"))
}
