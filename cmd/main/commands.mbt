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
/// 统一应用 `-p` / `-q` 过滤和 `-n` 截断。
fn select(history : @history.History, args : Args) -> Array[Int32] {
  let mut indexes = []
  for i, e in history.entries {
    if args.pinned_only && !e.pinned {
      continue
    }
    match args.query {
      Some(q) => if !e.text.contains(q) { continue }
      None => ()
    }
    indexes.push(i)
  }
  if args.limit > 0 && indexes.length() > args.limit {
    indexes = indexes[:args.limit].to_owned()
  }
  indexes
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
  run_watch(saved, watcher, interval)
  save(saved)
  0
}

///|
async fn run_watch(
  saved : @history.History,
  watcher : @watch.Watcher,
  interval : Int32,
) -> Unit {
  // 回调跑在 `watch_loop` 的子任务里，拿不到父任务的执行上下文；
  // 放进任务组里跑，`save` 才是真正被执行（而不是创建一个被丢弃的 future）。
  @async.with_task_group(fn(group) {
    group.spawn_bg(async fn() {
      @watch.watch_loop(
        watcher,
        interval,
        async fn(text) {
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
              // 立刻落盘：Ctrl-C 或崩溃都不会丢掉刚复制的东西
              save(saved)
            }
            None => eprintln("mtuck: 内容过长或为空，已忽略")
          }
          true
        },
        on_error=fn(msg) { eprintln("mtuck: 读剪贴板失败: \{msg}") },
      )
    })
  })
}

///|
async fn command_list(args : Args) -> Int32 {
  let history = load()
  // 旧版本写入的条目没做充分识别，这里按当前规则重新判定一遍，
  // 避免早已落盘的密钥继续明文显示。
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
  let indexes = select(history, args)
  if args.json {
    print_json_entries(history, indexes, full=args.full)
    return 0
  }
  if indexes.is_empty() {
    if history.is_empty() {
      println("历史为空。先跑 `mtuck watch` 开始记录。")
    } else {
      println("没有匹配的条目。")
    }
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
  if args.limit > 0 && history.len() > indexes.length() {
    println(
      "（共 \{history.len()} 条，只显示前 \{indexes.length()} 条；-n 0 看全部）",
    )
  }
  0
}

///|
async fn command_show(args : Args) -> Int32 {
  let indexes = resolve_indexes(args)
  match indexes {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      let history = load()
      for idx in list {
        match history.get(idx) {
          None => eprintln("mtuck: 没有第 \{idx} 条")
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
      0
    }
  }
}

///|
async fn command_copy(args : Args) -> Int32 {
  match resolve_indexes(args) {
    Err(msg) => {
      eprintln(msg)
      2
    }
    Ok(list) => {
      let history = load()
      match list {
        [idx] =>
          match history.get(idx) {
            None => {
              eprintln("mtuck: 没有第 \{idx} 条")
              2
            }
            Some(e) => {
              let code = copy_to_clipboard(e.text)
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
      with_history(fn(history) {
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
      if failed {
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
      with_history(fn(history) {
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
      println("已删除 \{removed} 条")
      if missing {
        2
      } else {
        0
      }
    }
  }
}

///|
async fn command_clear(args : Args) -> Int32 {
  let keep_pinned = !args.full
  with_history(fn(history) {
    let before = history.len()
    history.clear(keep_pinned~)
    let after = history.len()
    println("已清空 \{before - after} 条")
    if after > 0 {
      println(
        "保留固定条目 \{after} 条；`mtuck clear -f` 连固定的也删",
      )
    }
  })
  0
}

///|
async fn command_stats(args : Args) -> Int32 {
  let history = load()
  let mut pinned = 0
  let mut secrets = 0
  let mut bytes = 0
  let kinds : Map[String, Int32] = Map([])
  for e in history.entries {
    if e.pinned {
      pinned = pinned + 1
    }
    if e.is_secret {
      secrets = secrets + 1
    }
    bytes = bytes + e.text.length()
    let count = kinds.get(e.kind_label).unwrap_or(0)
    kinds[e.kind_label] = count + 1
  }
  if args.json {
    let out = StringBuilder()
    out.write_string("{\"total\":\{history.len()}")
    out.write_string(",\"pinned\":\{pinned},\"secret\":\{secrets}")
    out.write_string(",\"chars\":\{bytes}")
    out.write_string(",\"path\":\"\{json_escape(history_path())}\"")
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
  println("总字符   \{bytes}")
  println("存储     \{history_path()}")
  if !kinds.is_empty() {
    let pairs = kinds.to_array()
    pairs.sort_by(fn(a, b) { b.1.compare(a.1) })
    let parts = pairs.map(fn(p) { "\{p.0}×\{p.1}" })
    let line = parts.join("  ")
    println("类型分布 \{line}")
  }
  0
}
