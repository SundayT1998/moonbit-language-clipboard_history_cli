///|
async test "dispatch: help 与 version 返回 0" {
  for cmd in ["help", "--help", "-h", ""] {
    let code = dispatch(default_args(cmd))
    assert_eq(code, 0)
  }
  assert_eq(dispatch(default_args("version")), 0)
  assert_eq(dispatch(default_args("--version")), 0)
}

///|
async test "dispatch: 未知命令返回 2" {
  assert_eq(dispatch(default_args("frobnicate")), 2)
  // 大小写敏感：`List` 不是 `list`
  assert_eq(dispatch(default_args("List")), 2)
}

///|
async test "run: 参数错误返回 2，且不会碰到历史文件" {
  // `-n abc` 解析失败，`run` 直接返回 2
  assert_eq(run(["mtuck", "list", "-n", "abc"]), 2)
  // `argv[0]` 是程序名，`run` 只解析它后面的部分
  assert_eq(run([]), 0)
}
