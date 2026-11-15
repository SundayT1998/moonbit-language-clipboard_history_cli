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
