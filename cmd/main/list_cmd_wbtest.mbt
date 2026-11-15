///|
test "select: 默认全选并保持顺序" {
  let h = sample_history()
  assert_eq(select_with_count(h, default_args("list")).0, [0, 1, 2, 3])
}

///|
test "select: -n 截断，-n 0 表示全部" {
  let h = sample_history()
  assert_eq(select_with_count(h, { ..default_args("list"), limit: 2, }).0, [
    0, 1,
  ])
  assert_eq(
    select_with_count(h, { ..default_args("list"), limit: 0, }).0.length(),
    4,
  )
  assert_eq(
    select_with_count(h, { ..default_args("list"), limit: 99, }).0.length(),
    4,
  )
}

///|
test "select: -p 只看固定条目" {
  let h = sample_history()
  let picked = select_with_count(h, {
      ..default_args("list"),
      pinned_only: true,
    }).0
  assert_eq(picked, [0])
}

///|
test "select: -q 按子串过滤（大小写敏感）" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("git"), }
  assert_true(selected(h, args, "git status"))
  assert_false(selected(h, args, "pinned note"))
  let upper = { ..default_args("list"), query: Some("GIT"), }
  assert_true(select_with_count(h, upper).0.is_empty())
}

///|
test "select: 过滤与截断组合，先筛后截" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("example"), limit: 1, }
  // 只有 #3（最早写入的 URL）匹配
  assert_eq(select_with_count(h, args).0, [3])
}

///|
test "matched: 只过滤不截断" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("e"), limit: 1, }
  // 四条里有三条含 "e"（example / password / pinned），limit 不影响 matched
  assert_eq(matched(h, args).length(), 3)
  assert_eq(select_with_count(h, args).0, [0])
  let pinned = { ..default_args("list"), pinned_only: true, }
  assert_eq(matched(h, pinned), [0])
}

///|
test "select: 没有匹配时返回空" {
  let h = sample_history()
  let args = { ..default_args("list"), query: Some("nope"), }
  assert_true(select_with_count(h, args).0.is_empty())
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
async test "list 的行渲染：密钥打码、普通条目截断" {
  with_tmp_history(async fn(path) {
    let history = load_from(path)
    history.reclassify()
    let args = default_args("list")
    let rendered = select_with_count(history, args).0.map(fn(idx) {
      match history.get(idx) {
        Some(e) => entry_preview(e, false)
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

///|
test "entry_preview: 密钥打码、普通条目截断、-f 原样" {
  let h = sample_history()
  let secret = h.get(1).unwrap()
  assert_false(entry_preview(secret, false).contains("hunter2"))
  assert_eq(entry_preview(secret, true), "password=hunter2")
  let plain = h.get(2).unwrap()
  assert_eq(entry_preview(plain, false), "git status")
}
