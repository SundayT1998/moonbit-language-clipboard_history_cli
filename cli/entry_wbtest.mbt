///|
async test "run_inner: help 与 version 返回 0" {
  for cmd in ["help", "--help", "-h", ""] {
    assert_eq(run_inner(["mtuck", cmd]), 0)
  }
  assert_eq(run_inner(["mtuck", "version"]), 0)
  assert_eq(run_inner(["mtuck", "--version"]), 0)
}

///|
async test "run_inner: 未知命令返回 2" {
  assert_eq(run_inner(["mtuck", "frobnicate"]), 2)
  // 大小写敏感：`List` 不是 `list`
  assert_eq(run_inner(["mtuck", "List"]), 2)
}

///|
async test "run_inner: 参数错误返回 2，且不会碰到历史文件" {
  // `-n abc` 解析失败，直接返回 2
  assert_eq(run_inner(["mtuck", "list", "-n", "abc"]), 2)
  // `argv[0]` 是程序名，只解析它后面的部分；空参数等价于 `mtuck` 本身
  assert_eq(run_inner([]), 0)
}

///|
async test "run_inner: 命令只接受自己的选项，不支持的选项返回 2" {
  assert_eq(run_inner(["mtuck", "watch", "-q", "foo"]), 2)
  assert_eq(run_inner(["mtuck", "clear", "--json"]), 2)
  assert_eq(run_inner(["mtuck", "copy", "--nope"]), 2)
}
