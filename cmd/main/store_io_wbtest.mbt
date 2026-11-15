///|
/// 临时改环境变量，测试结束后恢复。
async fn[T] with_env(key : String, value : String?, f : async () -> T) -> T {
  let old = @env.get_env_var(key)
  match value {
    Some(v) => @env.set_env_var(key, v)
    None => @env.unset_env_var(key)
  }
  let result = f()
  match old {
    Some(v) => @env.set_env_var(key, v)
    None => @env.unset_env_var(key)
  }
  result
}

///|
async test "data_dir 优先使用 MTUCK_DIR" {
  with_env("MTUCK_DIR", Some("/tmp/mtuck-test-dir"), () => {
    assert_eq(data_dir(), "/tmp/mtuck-test-dir")
    assert_eq(history_path(), "/tmp/mtuck-test-dir/history.tsv")
  })
}

///|
async test "data_dir 忽略空的 MTUCK_DIR" {
  with_env("HOME", Some("/home/someone"), () => {
    with_env("MTUCK_DIR", Some(""), () => {
      assert_eq(data_dir(), "/home/someone/.local/share/mtuck")
    })
    with_env("MTUCK_DIR", None, () => {
      assert_eq(data_dir(), "/home/someone/.local/share/mtuck")
    })
  })
}

///|
async test "data_dir 没有 HOME 时兜底为绝对路径" {
  with_env("MTUCK_DIR", None, () => {
    with_env("HOME", Some(""), () => {
      // 相对路径会被补成 `$PWD/.mtuck`
      assert_eq(data_dir(), "\{@env.current_dir().unwrap()}/.mtuck")
    })
    with_env("HOME", None, () => {
      assert_eq(data_dir(), "\{@env.current_dir().unwrap()}/.mtuck")
    })
  })
}

///|
async test "data_dir 把相对的 MTUCK_DIR 补成绝对路径" {
  with_env("MTUCK_DIR", Some("relative/dir"), () => {
    assert_eq(data_dir(), "\{@env.current_dir().unwrap()}/relative/dir")
  })
}

///|
async test "data_dir 不改动已经是绝对路径的 MTUCK_DIR" {
  with_env("MTUCK_DIR", Some("/already/absolute"), () => {
    assert_eq(data_dir(), "/already/absolute")
  })
}

///|
async test "history_path 跟着 data_dir 走" {
  with_env("MTUCK_DIR", Some("/x/y"), () => {
    assert_eq(history_path(), "/x/y/history.tsv")
  })
}

///|
async test "data_dir 在没有任何目录配置时也能给出可写目录名" {
  with_env("MTUCK_DIR", None, () => {
    with_env("HOME", Some("/home/u"), () => {
      assert_eq(history_path(), "/home/u/.local/share/mtuck/history.tsv")
    })
  })
}

///|
/// 用显式路径的 `save_to` / `load_from` 测文件读写。这里不改进程环境变量：
/// 环境变量是全局状态，测试异步交错时会互相干扰。
async fn path_roundtrip(f : async (String) -> Unit) -> Unit {
  let dir = @fs.tmpdir(prefix="mtuck-test-") catch { e => abort(e.to_string()) }
  let path = "\{dir}/data/history.tsv"
  f(path)
  @fs.rmdir(dir, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
async test "load_from 在文件不存在时返回空历史" {
  path_roundtrip(async fn(path) {
    let h = load_from(path)
    assert_true(h.is_empty())
  })
}

///|
async test "save_to/load_from 往返，固定与密钥标记都保留" {
  path_roundtrip(async fn(path) {
    let h = @history.History::new()
    h.push("hello", 1L) |> ignore
    h.push("password=xyz", 2L) |> ignore
    h.toggle_pin(1)
    let dir = path[:path.rev_find("/").unwrap()].to_owned()
    save_to(h, path, dir)
    let back = load_from(path)
    assert_eq(back.len(), 2)
    assert_eq(back.get(0).unwrap().text, "password=xyz")
    assert_true(back.get(0).unwrap().is_secret)
    assert_eq(back.get(1).unwrap().text, "hello")
    assert_true(back.get(1).unwrap().pinned)
    // 临时文件已经被 rename 掉
    assert_false(@fs.exists("\{path}.tmp") catch { _ => true })
    // 文件带表头，与 encode 一致
    let raw = @fs.read_text(path)
    assert_true(raw.has_prefix("mtuck-history\t1\n"))
  })
}

///|
async test "save_to 覆盖旧文件而不是追加" {
  path_roundtrip(async fn(path) {
    let dir = path[:path.rev_find("/").unwrap()].to_owned()
    let old = @history.History::new()
    old.push("old", 1L) |> ignore
    old.push("older", 0L) |> ignore
    save_to(old, path, dir)
    let fresh = @history.History::new()
    fresh.push("new", 2L) |> ignore
    save_to(fresh, path, dir)
    let back = load_from(path)
    assert_eq(back.len(), 1)
    assert_eq(back.get(0).unwrap().text, "new")
  })
}

///|
async test "save_to 会创建缺失的多级目录" {
  path_roundtrip(async fn(path) {
    // path 是 "<tmp>/data/history.tsv"，data 目录还不存在
    let dir = path[:path.rev_find("/").unwrap()].to_owned()
    let h = @history.History::new()
    h.push("deep", 1L) |> ignore
    save_to(h, path, dir)
    assert_true(@fs.exists(path) catch { _ => false })
  })
}

///|
async test "load_from 跳过坏行，不会崩" {
  path_roundtrip(async fn(path) {
    let dir = path[:path.rev_find("/").unwrap()].to_owned()
    @fs.mkdir(dir, recursive=true, allow_exist=true)
    @fs.write_text(path, "garbage\n1\t1\t0\ttext\t0\tgood\n")
    let back = load_from(path)
    assert_eq(back.len(), 1)
    assert_eq(back.get(0).unwrap().text, "good")
  })
}
