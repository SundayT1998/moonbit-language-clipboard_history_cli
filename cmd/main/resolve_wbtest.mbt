///|
fn args_of(tokens : Array[String]) -> Args {
  { ..default_args("rm"), positional: tokens, }
}

///|
test "resolve_indexes 解析单个、多个与区间" {
  assert_eq(resolve_indexes(args_of(["0"])), Ok([0]))
  assert_eq(resolve_indexes(args_of(["1,3,5"])), Ok([1, 3, 5]))
  assert_eq(resolve_indexes(args_of(["1-3"])), Ok([1, 2, 3]))
  assert_eq(resolve_indexes(args_of(["last"])), Ok([0]))
}

///|
test "resolve_indexes 拒绝会撑爆内存的超长区间" {
  assert_true(
    resolve_indexes(args_of(["1-99999999"])) is Err(msg) &&
    msg.contains("过长"),
  )
  // 与历史上限对齐的区间仍然可用
  assert_true(resolve_indexes(args_of(["0-999"])) is Ok(_))
  assert_true(resolve_indexes(args_of(["1-abc"])) is Err(_))
}
