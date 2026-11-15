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

///|
test "resolve_indexes 支持别名、大小写与 -1" {
  assert_eq(resolve_indexes(args_of(["LATEST"])), Ok([0]))
  assert_eq(resolve_indexes(args_of(["-1"])), Ok([0]))
  assert_eq(resolve_indexes(args_of(["Last"])), Ok([0]))
}

///|
test "resolve_indexes 混合多个参数" {
  assert_eq(resolve_indexes(args_of(["0", "2-3", "5,6"])), Ok([0, 2, 3, 5, 6]))
  assert_eq(resolve_indexes(args_of(["last", "3"])), Ok([0, 3]))
}

///|
test "resolve_indexes 缺参数与非法输入" {
  assert_true(
    resolve_indexes(args_of([])) is Err(msg) && msg.contains("编号"),
  )
  assert_true(resolve_indexes(args_of(["abc"])) is Err(_))
  assert_true(resolve_indexes(args_of(["-5"])) is Err(_))
  assert_true(resolve_indexes(args_of(["1,"])) is Err(_))
  assert_true(resolve_indexes(args_of(["a,b"])) is Err(_))
}

///|
test "resolve_indexes 拒绝倒序区间" {
  assert_true(resolve_indexes(args_of(["5-1"])) is Err(_))
}

///|
test "resolve_indexes 容忍下标前后空白" {
  assert_eq(resolve_indexes(args_of([" 2 ", "3- 4"])), Ok([2, 3, 4]))
}

///|
test "resolve_indexes 单个区间上限边界" {
  // 区间长度正好等于历史上限时可用，再多一条就拒绝
  assert_true(resolve_indexes(args_of(["0-999"])) is Ok(_))
  assert_true(resolve_indexes(args_of(["0-1000"])) is Err(_))
}
