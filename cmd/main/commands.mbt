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
fn print_json_entries(
  history : @history.History,
  indexes : Array[Int32],
  full~ : Bool,
) -> Unit {
  let out = StringBuilder()
  out.write_string("[")
  let mut first = true
  for idx in indexes {
    match history.get(idx) {
      None => ()
      Some(e) => {
        if !first {
          out.write_string(",")
        }
        first = false
        out.write_string("{\"index\":\{idx},\"ts\":\{e.ts},\"hits\":\{e.hits}")
        out.write_string(",\"pinned\":\{e.pinned},\"kind\":\"\{e.kind_label}\"")
        out.write_string(",\"secret\":\{e.is_secret}")
        // 与列表视图一致：密钥默认打码，`-f` 才输出原文
        let text = if e.is_secret && !full {
          @history.mask(@history.summary(e.text, 24))
        } else {
          e.text
        }
        out.write_string(",\"redacted\":\{(text != e.text)}")
        out.write_string(",\"text\":\"\{json_escape(text)}\"}")
      }
    }
  }
  out.write_string("]")
  println(out.to_string())
}

///|
/// 应用 `-p` / `-q` 过滤，返回命中条目。不做 `-n` 截断。
fn matched(history : @history.History, args : Args) -> Array[Int32] {
  let out = []
  for i, e in history.entries {
    if args.pinned_only && !e.pinned {
      continue
    }
    match args.query {
      Some(q) => if !e.text.contains(q) { continue }
      None => ()
    }
    out.push(i)
  }
  out
}

///|
/// 统一应用 `-p` / `-q` 过滤和 `-n` 截断。
fn select(history : @history.History, args : Args) -> Array[Int32] {
  let indexes = matched(history, args)
  if args.limit > 0 && indexes.length() > args.limit {
    indexes[:args.limit].to_owned()
  } else {
    indexes
  }
}

///|
/// `list` 底部统计里的一条提示。`None` 表示没什么可说的（没有截断）。
///
/// 区分“匹配数”和“展示数”：过滤后的条目被 `-n` 截断时，
/// 只报过滤前的总数会让读者误以为命中了很多 / 很少。
fn list_footer(total : Int32, matched_count : Int32, shown : Int32) -> String? {
  if shown >= matched_count {
    return None
  }
  if matched_count == total {
    Some("（共 \{total} 条，只显示前 \{shown} 条；-n 0 看全部）")
  } else {
    Some(
      "（匹配 \{matched_count} 条，只显示前 \{shown} 条；-n 0 看全部）",
    )
  }
}

///|
/// 过滤后没有结果时的提示，区分“历史为空”“过滤条件太严”两种情况。
fn empty_list_hint(
  total : Int32,
  pinned_only : Bool,
  query : String?,
) -> String {
  if total == 0 {
    return "历史为空。先跑 `mtuck watch` 开始记录。"
  }
  let scope = if pinned_only { "固定条目" } else { "条目" }
  match query {
    Some(q) =>
      "没有匹配“\{q}”的\{scope}（共 \{total} 条历史）。"
    None => "没有\{scope}（共 \{total} 条历史）。"
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

///|
/// 读历史，并按当前规则重新判定未标记为密钥的条目。
///
/// 旧版本写入的条目没做充分识别，这里重判一遍，避免早已落盘的密钥继续明文显示。
fn reclassify(history : @history.History) -> Unit {
  for i, e in history.entries {
    if !e.is_secret {
      let kind = @history.classify(e.text)
      history.entries[i] = {
        ..e,
        kind_label: kind.label,
        is_secret: kind.is_secret,
      }
    }
  }
}

///|
async fn command_list(args : Args, path~ : String = history_path()) -> Int32 {
  let history = load_from(path)
  reclassify(history)
  let indexes = select(history, args)
  if args.json {
    print_json_entries(history, indexes, full=args.full)
    return 0
  }
  let hits = matched(history, args)
  if indexes.is_empty() {
    println(empty_list_hint(history.len(), args.pinned_only, args.query))
    return 0
  }
  let now = now_ms()
  for idx in indexes {
    match history.get(idx) {
      None => ()
      Some(e) => {
        let pin = if e.pinned { "★" } else { " " }
        let preview = if args.full {
          e.text
        } else if e.is_secret {
          @history.mask(@history.summary(e.text, 24))
        } else {
          @history.summary(e.text, 60)
        }
        println(
          "\{pin} #\{idx}  \{format_ago(e.ts, now)}  ×\{e.hits}  [\{e.kind_label}]  \{preview}",
        )
      }
    }
  }
  match list_footer(history.len(), hits.length(), indexes.length()) {
    Some(line) => println(line)
    None => ()
  }
  0
}

///|
async fn command_show(args : Args, path~ : String = history_path()) -> Int32 {
  let indexes = resolve_indexes(args)
  match indexes {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      let history = load_from(path)
      let mut missing = false
      for idx in list {
        match history.get(idx) {
          None => {
            eprintln("mtuck: 没有第 \{idx} 条")
            missing = true
          }
          Some(e) =>
            if e.is_secret && !args.full {
              println(
                "[本次剪贴板内容被识别为保密信息，用 -f 才会显示原文]",
              )
              println(@history.mask(e.text))
            } else {
              println(e.text)
            }
        }
      }
      // 与 pin / rm 一致：编号越界属于用法错误，脚本要能感知到
      if missing {
        2
      } else {
        0
      }
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
async fn command_pin(args : Args, pin : Bool) -> Int32 {
  match resolve_indexes(args) {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      let mut failed = false
      let saved = with_history(fn(history) {
        for idx in list {
          match history.get(idx) {
            None => {
              eprintln("mtuck: 没有第 \{idx} 条")
              failed = true
            }
            Some(e) => if e.pinned != pin { history.toggle_pin(idx) }
          }
        }
      })
      if saved is Err(msg) {
        // 写盘失败时不能再打印“已固定”，否则用户会以为成功了
        eprintln("mtuck: \{msg}")
        1
      } else if failed {
        2
      } else {
        if pin {
          println("已固定 \{list.length()} 条")
        } else {
          println("已取消固定 \{list.length()} 条")
        }
        0
      }
    }
  }
}

///|
async fn command_remove(args : Args) -> Int32 {
  match resolve_indexes(args) {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      // 从大到小删，避免边删边改下标
      let sorted = list.copy()
      sorted.sort_by(fn(a, b) { b.compare(a) })
      let mut removed = 0
      let mut missing = false
      let saved = with_history(fn(history) {
        for idx in sorted {
          // 删除会改变下标，所以按降序处理；越界的编号单独报出来
          if idx >= history.len() {
            eprintln("mtuck: 没有第 \{idx} 条")
            missing = true
          } else {
            history.remove_at(idx)
            removed = removed + 1
          }
        }
      })
      match saved {
        Err(msg) => {
          eprintln("mtuck: \{msg}")
          1
        }
        Ok(_) => {
          println("已删除 \{removed} 条")
          if missing {
            2
          } else {
            0
          }
        }
      }
    }
  }
}

///|
async fn command_clear(args : Args) -> Int32 {
  let keep_pinned = !args.full
  // 成败都在回调里打印：写盘失败时不能再说“已清空”
  let mut report : () -> Unit = fn() { () }
  let saved = with_history(fn(history) {
    let before = history.len()
    history.clear(keep_pinned~)
    let after = history.len()
    report = fn() {
      println("已清空 \{before - after} 条")
      if after > 0 {
        println(
          "保留固定条目 \{after} 条；`mtuck clear -f` 连固定的也删",
        )
      }
    }
  })
  match saved {
    Ok(_) => {
      report()
      0
    }
    Err(msg) => {
      eprintln("mtuck: \{msg}")
      1
    }
  }
}

///|
async fn command_stats(args : Args, path~ : String = history_path()) -> Int32 {
  let history = load_from(path)
  let mut pinned = 0
  let mut secrets = 0
  let mut chars = 0
  let mut bytes = 0
  let kinds : Map[String, Int32] = Map([])
  for e in history.entries {
    if e.pinned {
      pinned = pinned + 1
    }
    if e.is_secret {
      secrets = secrets + 1
    }
    // 字符数与 UTF-8 字节数口径不同：单条上限按字节算，这里两个都报
    chars = chars + e.text.length()
    bytes = bytes + @utf8.encode(e.text).length()
    let count = kinds.get(e.kind_label).unwrap_or(0)
    kinds[e.kind_label] = count + 1
  }
  if args.json {
    let out = StringBuilder()
    out.write_string("{\"total\":\{history.len()}")
    out.write_string(",\"pinned\":\{pinned},\"secret\":\{secrets}")
    out.write_string(",\"chars\":\{chars}")
    out.write_string(",\"bytes\":\{bytes}")
    out.write_string(",\"path\":\"\{json_escape(path)}\"")
    out.write_string(",\"kinds\":{")
    let mut first = true
    for k, v in kinds {
      if !first {
        out.write_string(",")
      }
      first = false
      out.write_string("\"\{json_escape(k)}\":\{v}")
    }
    out.write_string("}}")
    println(out.to_string())
    return 0
  }
  println("条目     \{history.len()} / \{@history.max_entries}")
  println("已固定   \{pinned}")
  println("疑似密钥 \{secrets}")
  println("总字符   \{chars}")
  println("总字节   \{bytes}")
  println("存储     \{path}")
  if !kinds.is_empty() {
    let pairs = kinds.to_array()
    pairs.sort_by(fn(a, b) { b.1.compare(a.1) })
    let parts = pairs.map(fn(p) { "\{p.0}×\{p.1}" })
    let line = parts.join("  ")
    println("类型分布 \{line}")
  }
  0
}
