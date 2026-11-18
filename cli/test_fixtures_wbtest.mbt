///|
/// 测试夹具：多个命令的测试共用，集中放这里，避免各文件各造一份。
///
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
  select_with_count(history, args).0.any(fn(i) {
    match history.get(i) {
      Some(e) => e.text == text
      None => false
    }
  })
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
  // `tmpdir` 已经建好目录，不必再 mkdir
  let dir = @fs.tmpdir(prefix="mtuck-test-") catch { e => abort(e.to_string()) }
  let path = "\{dir}/history.tsv"
  assert_true(save_to(sample_history(), path, dir))
  f(path)
  @fs.remove(dir, recursive=true) catch {
    _ => ()
  }
}
