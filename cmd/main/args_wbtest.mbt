///|
test "parse_args 正常解析" {
  let args = parse_args(["list", "-n", "5", "-f", "--json"])
  assert_true(args is Ok(a) && a.limit == 5 && a.full && a.json)
  let args2 = parse_args(["list", "--query"])
  assert_true(args2 is Err(_))
}

///|
test "parse_args 拒绝非法或缺失的取值" {
  assert_true(
    parse_args(["list", "-n", "abc"]) is Err(msg) && msg.contains("abc"),
  )
  assert_true(parse_args(["list", "-n"]) is Err(_))
  assert_true(parse_args(["list", "-n", "-5"]) is Err(_))
  assert_true(parse_args(["list", "-q"]) is Err(_))
  // 合法取值不受影响
  assert_true(parse_args(["list", "-n", "0"]) is Ok(a) && a.limit == 0)
}

///|
test "watch 间隔用独立选项，不再与 -n 冲突" {
  assert_true(parse_args(["watch", "-n", "5"]) is Ok(a) && a.interval is None)
  assert_true(
    parse_args(["watch", "--interval", "100"]) is Ok(a) &&
    a.interval is Some(100),
  )
  assert_true(parse_args(["watch", "-i", "0"]) is Err(_))
  assert_true(parse_args(["watch", "-i", "abc"]) is Err(_))
}

///|
fn ok(argv : Array[String]) -> Args {
  match parse_args(argv) {
    Ok(a) => a
    Err(msg) => abort("预期解析成功，实际报错: \{msg}")
  }
}

///|
test "parse_args 默认值" {
  let a = ok(["list"])
  assert_eq(a.command, "list")
  assert_eq(a.limit, 20)
  assert_false(a.full)
  assert_false(a.pinned_only)
  assert_true(a.query is None)
  assert_false(a.json)
  assert_true(a.interval is None)
  assert_true(a.positional.is_empty())
  // 没有参数时命令为空串，main 会打印帮助
  assert_eq(ok([]).command, "")
}

///|
test "parse_args 支持 --opt=value 写法" {
  assert_eq(ok(["list", "--limit=7"]).limit, 7)
  assert_eq(ok(["list", "--query=foo bar"]).query, Some("foo bar"))
  assert_eq(ok(["watch", "--interval=250"]).interval, Some(250))
  // 空值也按“给了取值”处理，由各选项自己校验
  assert_true(parse_args(["list", "--limit="]) is Err(_))
  assert_eq(ok(["list", "--query="]).query, Some(""))
}

///|
test "parse_args 拒绝给不带取值的选项塞值" {
  assert_true(
    parse_args(["list", "--full=1"]) is Err(msg) && msg.contains("--full"),
  )
  assert_true(parse_args(["list", "--json=x"]) is Err(_))
}

///|
test "parse_args 收集位置参数并保留顺序" {
  let a = ok(["rm", "1", "3-5", "7,8"])
  assert_eq(a.positional, ["1", "3-5", "7,8"])
}

///|
test "parse_args 把 -- 之后的内容都当作位置参数" {
  let a = ok(["rm", "--", "-n", "-1"])
  // `-n` 不再被当成选项，原样进位置参数
  assert_eq(a.positional, ["-n", "-1"])
  assert_eq(a.limit, 20)
}

///|
test "parse_args 忽略未知选项但保留单个 -" {
  let a = ok(["list", "--wat", "-"])
  // `-` 习惯上表示 stdin，当位置参数处理
  assert_eq(a.positional, ["-"])
}

///|
test "parse_args 组合短选项" {
  let a = ok(["list", "-f", "-p", "-q", "abc", "-n", "3"])
  assert_true(a.full)
  assert_true(a.pinned_only)
  assert_eq(a.query, Some("abc"))
  assert_eq(a.limit, 3)
}

///|
test "parse_args 的间隔上限" {
  assert_eq(ok(["watch", "-i", "60000"]).interval, Some(60000))
  assert_true(parse_args(["watch", "-i", "60001"]) is Err(_))
  assert_true(parse_args(["watch", "-i", "-1"]) is Err(_))
}

///|
test "parse_args 不支持短选项与取值粘连" {
  // `-n5` 整体被当作未知选项忽略，不会误读成 `-n 5`
  let a = ok(["list", "-n5"])
  assert_eq(a.limit, 20)
  assert_true(a.positional.is_empty())
}
