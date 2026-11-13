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
