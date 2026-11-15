///|
async test "with_history_at: 读-改-写三步" {
  with_tmp_history(async fn(path) {
    with_history_at(path, fn(h) {
      h.push("newest", 1_700_000_400_000L) |> ignore
    })
    let back = load_from(path)
    assert_eq(back.len(), 5)
    assert_eq(back.get(0).unwrap().text, "newest")
    // 再改一次，确认是读-改-写而不是覆盖
    with_history_at(path, fn(h) {
      match h.search("pinned note").get(0) {
        Some(i) => h.toggle_pin(i)
        None => ()
      }
    })
    let back2 = load_from(path)
    assert_eq(back2.len(), 5)
    assert_false(back2.get(4).unwrap().pinned)
  })
}

///|
async test "删除多条：降序删除不会错位" {
  with_tmp_history(async fn(path) {
    // 模拟 `rm 0 2`：先删大的下标
    with_history_at(path, fn(h) {
      let sorted = [0, 2]
      sorted.sort_by(fn(a, b) { b.compare(a) })
      for idx in sorted {
        h.remove_at(idx)
      }
    })
    let back = load_from(path)
    assert_eq(back.len(), 2)
    // 原顺序是 [pinned note, password=hunter2, git status, URL]，
    // 删掉 #0 和 #2 之后剩 #1 和 #3
    assert_eq(back.get(0).unwrap().text, "password=hunter2")
    assert_eq(back.get(1).unwrap().text, "https://example.com/docs")
  })
}

///|
async test "clear: 默认保留固定条目，-f 全清" {
  with_tmp_history(async fn(path) {
    with_history_at(path, fn(h) { h.clear(keep_pinned=true) })
    let back = load_from(path)
    assert_eq(back.len(), 1)
    assert_true(back.get(0).unwrap().pinned)
    with_history_at(path, fn(h) { h.clear(keep_pinned=false) })
    assert_true(load_from(path).is_empty())
  })
}

///|
async test "保存再读取后分类信息还在，密钥仍被打码" {
  with_tmp_history(async fn(path) {
    let back = load_from(path)
    back.reclassify()
    let secret = back.search("password=hunter2").get(0).unwrap()
    let e = back.get(secret).unwrap()
    assert_true(e.is_secret)
    assert_false(@history.mask(e.text).contains("hunter2"))
    assert_true(@history.mask(e.text).has_prefix("pass"))
  })
}

///|
async test "command_show: 编号越界返回退出码 2，与 pin / rm 一致" {
  with_tmp_history(async fn(path) {
    // 下标的有效性取决于加载后的历史，这里直接换一份只有两条的文件
    let two = @history.History::new()
    two.push("first", 1_700_000_000_000L) |> ignore
    two.push("second", 1_700_000_100_000L) |> ignore
    let dir = path[:path.rev_find("/").unwrap_or(0)].to_owned()
    assert_true(save_to(two, path, dir))
    let args = { ..default_args("show"), positional: ["0"], }
    assert_eq(command_show(args, path~), 0)
    let missing = { ..default_args("show"), positional: ["5"], }
    assert_eq(command_show(missing, path~), 2)
  })
}
