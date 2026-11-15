///|
/// 可执行入口。真正的逻辑在 `mtuck/cli`，这里只转交参数并设置退出码。
async fn main {
  let code = @cli.run(@env.args())
  @env.exit(code)
}
