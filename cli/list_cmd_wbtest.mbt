///|
/// `list` 命令本身的退出码与边界行为。过滤 / 截断 / 提示文案的纯逻辑在
/// `list_select_wbtest.mbt`；这里走 `command_list`，把历史文件路径和“现在”
/// 都注入进去，不碰进程环境变量。
async fn list_at(path : String, args : Args) -> Int32 {
  command_list(args, path~, now=1_700_000_400_000L)
}

///|
async test "command_list: 正常列出返回 0" {
  with_tmp_history(async fn(path) {
    assert_eq(list_at(path, default_args("list")), 0)
    assert_eq(list_at(path, { ..default_args("list"), json: true, }), 0)
  })
}

///|
async test "command_list: 没有匹配仍返回 0，空历史也一样" {
  with_tmp_history(async fn(path) {
    let args = { ..default_args("list"), query: Some("nope"), }
    assert_eq(list_at(path, args), 0)
  })
  // 文件不存在：当成空历史，不是错误
  let dir = @fs.tmpdir(prefix="mtuck-test-") catch { e => abort(e.to_string()) }
  let path = "\{dir}/absent/history.tsv"
  assert_eq(list_at(path, default_args("list")), 0)
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}
