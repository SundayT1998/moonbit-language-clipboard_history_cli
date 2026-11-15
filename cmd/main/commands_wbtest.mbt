///|
/// 造一份固定的历史：三条未固定 + 一条固定，时间戳是过去某个时刻。
fn sample_history() -> @history.History {
  let h = @history.History::new()
  h.push("https://example.com/docs", 1_700_000_000_000L) |> ignore
  h.push("git status", 1_700_000_100_000L) |> ignore
  h.push("password=hunter2", 1_700_000_200_000L) |> ignore
  h.push("pinned note", 1_700_000_300_000L) |> ignore
  // toggle_pin 作用于下标 0（最新一条）
  h.toggle_pin(0)
  h
}

///|
/// 在下标集合里查某个文本是否被选中。
fn selected(history : @history.History, args : Args, text : String) -> Bool {
  select(history, args).any(fn(i) {
    match history.get(i) {
      Some(e) => e.text == text
      None => false
    }
  })
}

///|
test "select: 默认全选并保持顺序" {
  let h = sample_history()
  assert_eq(select(h, default_args("list")), [0, 1, 2, 3])
}

///|
test "select: -n 截断，-n 0 表示全部" {
  let h = sample_history()
  assert_eq(select(h, { ..default_args("list"), limit: 2, }), [0, 1])
  assert_eq(select(h, { ..default_args("list"), limit: 0, }).length(), 4)
  assert_eq(select(h, { ..default_args("list"), limit: 99, }).length(), 4)
}

///|
test "select: -p 只看固定条目" {
  let h = sample_history()
  let picked = select(h, { ..default_args("list"), pinned_only: true, })
  assert_eq(picked, [0])
}

///|
test "select: -q 按子串过滤（大小写敏感）" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("git"), }
  assert_true(selected(h, args, "git status"))
  assert_false(selected(h, args, "pinned note"))
  let upper = { ..default_args("list"), query: Some("GIT"), }
  assert_true(select(h, upper).is_empty())
}

///|
test "select: 过滤与截断组合，先筛后截" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("example"), limit: 1, }
  // 只有 #3（最早写入的 URL）匹配
  assert_eq(select(h, args), [3])
}

///|
test "matched: 只过滤不截断" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("e"), limit: 1, }
  // 四条里有三条含 "e"（example / password / pinned），limit 不影响 matched
  assert_eq(matched(h, args).length(), 3)
  assert_eq(select(h, args), [0])
  let pinned = { ..default_args("list"), pinned_only: true, }
  assert_eq(matched(h, pinned), [0])
}

///|
test "list_footer: 区分匹配数与展示数" {
  // 没有截断：不提示
  assert_true(list_footer(5, 5, 5) is None)
  assert_true(list_footer(5, 2, 2) is None)
  // 没过滤、被 -n 截断：沿用“共 N 条”
  assert_eq(
    list_footer(5, 5, 2),
    Some("（共 5 条，只显示前 2 条；-n 0 看全部）"),
  )
  // 过滤命中 3 条、展示 2 条：报匹配数，而不是全量 5 条
  assert_eq(
    list_footer(5, 3, 2),
    Some("（匹配 3 条，只显示前 2 条；-n 0 看全部）"),
  )
}

///|
test "empty_list_hint: 区分空历史、无匹配与无固定条目" {
  assert_eq(
    empty_list_hint(0, false, None),
    "历史为空。先跑 `mtuck watch` 开始记录。",
  )
  assert_eq(
    empty_list_hint(5, false, Some("nope")),
    "没有匹配“nope”的条目（共 5 条历史）。",
  )
  assert_eq(
    empty_list_hint(5, true, None),
    "没有固定条目（共 5 条历史）。",
  )
  assert_eq(
    empty_list_hint(5, true, Some("nope")),
    "没有匹配“nope”的固定条目（共 5 条历史）。",
  )
}

///|
test "select: 没有匹配时返回空" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("nope"), }
  assert_true(select(h, args).is_empty())
}

///|
test "reclassify: 旧条目按当前规则重新打上密钥标记" {
  let h = @history.History::new()
  // 直接塞一条“当时没识别成密钥”的条目
  h.entries.push({
    text: "sk-ant-abcdefghijklmnop",
    ts: 1L,
    hits: 1,
    pinned: false,
    kind_label: "text",
    is_secret: false,
  })
  h.entries.push({
    text: "https://example.com",
    ts: 2L,
    hits: 1,
    pinned: false,
    kind_label: "old-label",
    is_secret: false,
  })
  reclassify(h)
  assert_true(h.get(0).unwrap().is_secret)
  assert_eq(h.get(0).unwrap().kind_label, "secret")
  assert_eq(h.get(1).unwrap().kind_label, "url")
}

///|
test "reclassify: 不覆盖已经标记为密钥的条目" {
  let h = @history.History::new()
  h.entries.push({
    text: "plain text now",
    ts: 1L,
    hits: 1,
    pinned: false,
    kind_label: "secret",
    is_secret: true,
  })
  reclassify(h)
  assert_true(h.get(0).unwrap().is_secret)
  assert_eq(h.get(0).unwrap().kind_label, "secret")
}

///|
/// 读-改-写：以给定路径为准（测试用临时目录，线上用默认路径）。
async fn with_history_at(
  path : String,
  action : async (@history.History) -> Unit,
) -> Unit {
  let history = load_from(path)
  action(history)
  let dir = path[:path.rev_find("/").unwrap_or(0)].to_owned()
  assert_true(save_to(history, path, dir))
}

///|
async fn with_tmp_history(f : async (String) -> Unit) -> Unit {
  let dir = @fs.tmpdir(prefix="mtuck-test-") catch { e => abort(e.to_string()) }
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let path = "\{dir}/history.tsv"
  assert_true(save_to(sample_history(), path, dir))
  f(path)
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

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
    reclassify(back)
    let secret = back.search("password=hunter2").get(0).unwrap()
    let e = back.get(secret).unwrap()
    assert_true(e.is_secret)
    assert_false(@history.mask(e.text).contains("hunter2"))
    assert_true(@history.mask(e.text).has_prefix("pass"))
  })
}

///|
async test "list 的行渲染：密钥打码、普通条目截断" {
  with_tmp_history(async fn(path) {
    let history = load_from(path)
    reclassify(history)
    let args = default_args("list")
    let rendered = select(history, args).map(fn(idx) {
      match history.get(idx) {
        Some(e) =>
          if e.is_secret {
            @history.mask(@history.summary(e.text, 24))
          } else {
            @history.summary(e.text, 60)
          }
        None => ""
      }
    })
    assert_false(rendered.contains("password=hunter2"))
    assert_true(rendered.contains("git status"))
    assert_true(rendered.contains("https://example.com/docs"))
    // 固定条目的内容也能正常显示
    assert_true(rendered.contains("pinned note"))
  })
}
