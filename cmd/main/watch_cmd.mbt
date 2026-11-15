///|
async fn copy_to_clipboard(text : String) -> Int32 {
  match @clip.write_text(text) {
    Ok(_) => 0
    Err(msg) => {
      eprintln("mtuck: 写剪贴板失败: \{msg}")
      1
    }
  }
}

///|
async fn command_copy(
  args : Args,
  path~ : String = history_path(),
  write~ : async (String) -> Int32 = copy_to_clipboard,
) -> Int32 {
  match resolve_indexes(args) {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      let history = load_from(path)
      match list {
        [idx] =>
          match history.get(idx) {
            None => {
              eprintln("mtuck: 没有第 \{idx} 条")
              2
            }
            Some(e) => {
              let code = write(e.text)
              if code == 0 {
                println("已写回剪贴板：#\{idx}")
              }
              code
            }
          }
        _ => {
          eprintln("mtuck: copy 需要且只需要一个条目编号")
          2
        }
      }
    }
  }
}

///|
async fn command_watch(args : Args) -> Int32 {
  let interval = match args.interval {
    Some(ms) => ms
    None => 400
  }
  let history = load()
  let initial : String? = match @clip.read_text() {
    Ok(Some(text)) => Some(text)
    _ => None
  }
  let watcher = @watch.Watcher::new(async fn() { @clip.read_text() }, initial~)
  println(
    "监听剪贴板中（每 \{interval}ms 检查一次，Ctrl-C 退出）",
  )
  if !history.is_empty() {
    println("已有 \{history.len()} 条历史")
  }
  let saved = history
  let loop_failed = run_watch(saved, watcher, interval)
  if save(saved) && !loop_failed {
    0
  } else {
    1
  }
}

///|
async fn run_watch(
  saved : @history.History,
  watcher : @watch.Watcher,
  interval : Int32,
) -> Bool {
  // 轮询和落盘拆成两个任务：消费者按序把 `saved` 写进磁盘，轮询只负责
  // `poll` + `push`，写完一条再去读剪贴板。回调里直接 `save` 的话，一次
  // 全量编码 + 写临时文件 + fsync 期间读不到剪贴板，连续复制的中间内容会丢。
  //
  // 队列（`Blocking(1)`）满时消费者还没写完上一份：这时轮询后面的一次复制
  // 会先把内存写进队列，因此磁盘上最终一定有最近一次的内存状态。
  // 最坏情况是队列满的那个窗口里磁盘落后于内存，但内存里的条目一条不少，
  // 退出前也一定有一次完整落盘（退出后再存一次）。
  let queue : @aqueue.Queue[@history.History] = @aqueue.Queue::Queue(
    kind=Blocking(1),
  )
  let mut save_failed = false
  @async.with_task_group(fn(group) {
    // 消费者：每拿到一份快照就写一次盘，队列关闭后 `try_get` 抛错表示结束
    group.spawn_bg(async fn() {
      let running = Ref(true)
      while running.val {
        let entry = queue.try_get() catch {
          _ => {
            running.val = false
            None
          }
        }
        if entry is Some(entry) && !save(entry) {
          save_failed = true
        }
      }
    })
    group.spawn_bg(async fn() {
      @watch.watch_loop(
        watcher,
        interval,
        fn(text) {
          let result = saved.push(text, now_ms())
          match result {
            Some(_) => {
              let kind = @history.classify(text)
              let preview = @history.summary(text, 48)
              if kind.is_secret {
                println(
                  "+ [\{kind.label}] \{@history.mask(preview)}  (\{text.length()} 字符)",
                )
              } else {
                println("+ [\{kind.label}] \{preview}")
              }
              // 不阻塞轮询：队列满了（上一份还没写完）就等下一次复制，
              // 下一次交付的是最新内存状态，旧快照里多出来的条目不会丢
              let queued = queue.try_put(saved) catch { _ => false }
              queued |> ignore
            }
            None => eprintln("mtuck: 内容过长或为空，已忽略")
          }
          true
        },
        on_error=fn(msg) { eprintln("mtuck: 读剪贴板失败: \{msg}") },
      )
      queue.close()
    })
  })
  save_failed
}
