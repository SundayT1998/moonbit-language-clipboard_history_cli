# 项目问题记录

> 记录时间：2026-11-15
> 基线：`main` @ `cce8913`（命令名已从 `hk` 改为 `mtuck`）
> 方法：通读仓库 + 实际编译、跑测试 + 构造边界场景实测。
> `moon check` / `moon test` 均通过（18/18），下列问题都不在现有测试覆盖范围内。
>
> 标记「实测」的条目已在本地复现；标记「静态」的条目来自读代码推断，未跑到真实路径。

## 优先级总览

| # | 问题 | 级别 | 验证方式 |
|---|---|---|---|
| 1 | `now_ms` 多除了一次 1000，时间显示恒为「刚刚」 | 高 | 实测 |
| 2 | `json_escape` 对控制字符输出非法 JSON | 高 | 实测 |
| 3 | 多类常见密钥识别不出，原文直接显示 | 高 | 实测 |
| 4 | `watch` 读失败时每轮重复打印同一错误 | 低 | 实测 |
| 5 | `watch` 回调里的 `save` 未 await，「立刻落盘」未兑现 | 中 | 静态 |
| 6 | 下标区间无上限，可撑爆内存 | 中 | 实测 |
| 7 | 部分命令越界不报错、退出码为 0 | 低 | 实测 |
| 8 | 参数解析静默容错（`-n abc`、缺值） | 低 | 实测 |
| 9 | `watch -n` 与 `list -n` 语义冲突 | 低 | 静态 |
| 10 | 注释 / 文档与实现不符 | 低 | 静态 |
| 11 | 历史文件明文存储，权限未收紧 | 安全 | 实测 |
| 12 | CI 使用 `curl \| bash` 与未固定版本的可执行文件 | 安全 | 静态 |
| 13 | `.cnb.yml` 与 GitHub Actions 检查项重复维护 | 维护性 | 静态 |

建议修复顺序：**2 → 1 → 3 → 5**。2、1 改动小、风险低；3、5 影响安全性和核心功能。

---

## 高优先级

### 1. `now_ms` 时间戳量纲错误，历史条目恒显示「刚刚」

位置：[cmd/main/format.mbt:21-24](../cmd/main/format.mbt#L21-L24)

```moonbit
/// `@env.now()` 返回的是**微秒**，先降到毫秒再转 `Int64`。
pub fn now_ms() -> Int64 {
  let nanos = @env.now()
  (nanos / 1000UL).reinterpret_as_int64()
}
```

注释写 `@env.now()` 返回微秒，但实测 `@env.now()` 本身已是**毫秒**级的 Unix 时间（约 1.7e12）。再整除 1000 后变成约 1.7e9。

影响：

- `format_ago` 拿到的差值极大，实测所有条目都显示「刚刚」；
- `watch` 写入的 `ts` 与从文件读入的真实毫秒时间戳量纲不一致，混合条目排序 / 显示都会失真。

**修复方向**：去掉 `/ 1000UL`，改用 `@env.now().to_int64()`；补一条断言量级的测试（例如结果应 > 1e12）。

### 2. `json_escape` 对控制字符输出非法 JSON

位置：[cmd/main/format.mbt:28-47](../cmd/main/format.mbt#L28-L47)

```moonbit
if c.to_int() < 0x20 {
  out.write_string("\\u00")
  out.write_char(if c.to_int() < 0x10 { '0' } else { '0' })  // 两个分支相同
}
```

两个分支恒为 `'0'`，只写了一位十六进制。实测：

| 输入 | 输出 | 说明 |
|---|---|---|
| `a\x01` | `"a\u000"` | 少一位 |
| `b\x1f` 后接 `c` | `"b\u000c"` | 错位，吞掉后面的 `c` |

`jq` 等下游解析器会直接失败。

**修复方向**：按两位十六进制写出（`\u00` + 高 4 位 + 低 4 位）；补测试覆盖 `\x00`、`\x09`、`\x0f`、`\x1f`。

### 3. 保密信息识别覆盖率不足，敏感内容明文显示

位置：[history/kind.mbt:64-127](../history/kind.mbt#L64-L127)

实测以下内容均判定为 `text`、不打码，`mtuck list` 直接显示原文：

| 输入 | 期望 | 实际原因 |
|---|---|---|
| `authorization: bearer abcdefghijklmnop` | secret | 关键词表只有 `token` 等，认不出 bearer |
| `sk-ant-abcdefghijklmnopqrstuvwxyz` | secret | 没有裸密钥（前缀模式）规则 |
| `https://example.com/?token=abcdefghijklmnop` | secret | 以 `scheme://` 开头直接返回 `url`，跳过 `=` 检测 |
| `mongodb+srv://admin:hunter2@cluster0.mongodb.net` | secret | `@` 检测在 `first` 上做，但 `+` 让 scheme 不在明文白名单，落到 `dsn` 且 `is_secret=false` |

另外 `mtuck list --json` 完全不参考 `is_secret`（[cmd/main/commands.mbt:13-37](../cmd/main/commands.mbt#L13-L37)），上述内容在 `--json` 下也原样输出。

**修复方向**：

- 先做敏感子串检测（`bearer`、`authorization`、`token=`、`sk-`、`ghp_`、`AKIA` 等），再判 URL/DSN；
- DSN 判定改为检查 `://` 之后是否含 `user:pass@`，而不是看 scheme 白名单；
- `--json` 也套用打码，或在 help 中明确说明 JSON 输出不做脱敏。

---

## 中优先级

### 4. `watch` 读失败时每轮重复打印同一错误

位置：[watch/watch.mbt:67-92](../watch/watch.mbt#L67-L92)

`poll` 在读剪贴板失败（`Failed`）时没有更新 `last_token`，下一轮 token 仍不同，于是再次进入读取分支并再次失败。`watch_loop` 中「只在错误状态切换时触发一次」的设计因此失效。实测在无剪贴板后端的机器上，日志每轮新增一行相同错误。

**修复方向**：失败时同样更新 `last_token`，或在 `poll` 内部维护独立的错误去重状态。

### 5. `watch` 回调里的 `save` 未 await，「立刻落盘」未兑现

位置：[cmd/main/commands.mbt:79-104](../cmd/main/commands.mbt#L79-L104)

```moonbit
async fn(text) {
  ...
  // 立刻落盘：Ctrl-C 或崩溃都不会丢掉刚复制的东西
  save(saved)   // async 函数未 await / spawn
  true
}
```

`save` 是 async 函数，未 await / spawn 时只是创建了 future 并丢弃。Ctrl-C 之后不会再有新内容，循环退出后的 `save(saved)` 也只保存到那一刻为止，因此「Ctrl-C 或崩溃都不会丢掉刚复制的东西」的承诺没有实现。

另外每次都是全量 `save(saved)` 串行编码：1000 条 × 单条最大 256KB 时，每次写盘都要重新编码整个历史。

**修复方向**：改为 await 或 spawn 后台任务；长期可考虑增量追加写入。

> 注：本机无 X server，无法读到真实剪贴板，此条由读代码得出，建议在本地验证。

### 6. 下标区间无上限，可撑爆内存

位置：[cmd/main/resolve.mbt:25-29](../cmd/main/resolve.mbt#L25-L29)

实测 `mtuck rm 1-99999999` 在报错之前已经把近一亿个下标压入数组，耗时约 3.5 秒、CPU 100%。

**修复方向**：为区间长度设置上限（例如与 `max_entries` 对齐），或先校验上界再展开。

---

## 低优先级 / 体验

### 7. 部分命令越界不报错、退出码为 0

实测 `mtuck rm 7`（历史仅 5 条）输出「已删除 0 条」，退出码 0。而 README 的退出码表写明「2 = 条目不存在」。`show` / `copy` 对越界会报错，`rm` / `pin` 不会，行为不一致，脚本难以判断成败。

### 8. 参数解析静默容错

位置：[cmd/main/args.mbt:31-65](../cmd/main/args.mbt#L31-L65)

- `-n abc` 解析失败后静默保留默认值 20（实测）；
- `-n` / `-q` 位于末尾缺少取值时静默忽略。

建议至少打印警告，或返回非零退出码。

### 9. `watch -n` 与 `list -n` 语义冲突

位置：[cmd/main/commands.mbt:61-65](../cmd/main/commands.mbt#L61-L65)

`watch` 下 `-n` 被复用为轮询间隔（毫秒），而 help 中 `-n, --limit` 描述的是列表条数。`watch -n 0` 会退化为 20ms 一次，`watch -n 500` 为 500ms。建议引入独立的轮询间隔参数，并在 help 中说明。

### 10. 注释 / 文档与实现不符

- [history/codec.mbt:2](../history/codec.mbt#L2)：注释写「竖线、`#` 开头需要处理」，实际未处理 `|`，转义表只有 `\`、`\n`、`\r`、`\t`；
- [watch/watch.mbt:64-66](../watch/watch.mbt#L64-L66)：注释只提 Linux 依赖 `xclip`，实际后端还支持 `wl-paste` / `xsel`；
- [cmd/main/format.mbt:20](../cmd/main/format.mbt#L20)：`@env.now()` 的「微秒」说法有误（见第 1 条）。

---

## 安全 / 仓库卫生

### 11. 历史文件明文存储，权限未收紧

`~/.local/share/mtuck/history.tsv` 中含密码、token 原文。`@fs.mkdir` 使用进程默认 umask，实测生成目录 `drwxr-xr-x`、文件 `-rw-r--r--`，同机其他用户可读。

建议：

- 建目录时显式设置 0700，文件写入后设为 0600；
- 评估是否提供加密存储，或「敏感内容永不落盘」选项；
- `MTUCK_DIR` 直接取自环境变量，注意多用户场景下被意外覆盖。

### 12. CI 供应链风险

- [.github/workflows/check.yml:20](../.github/workflows/check.yml#L20) 与 [.ide/Dockerfile:7](../.ide/Dockerfile#L7)：`curl ... | bash` 直接执行下载的安装脚本；
- [.ide/Dockerfile:9-10](../.ide/Dockerfile#L9-L10)：执行 claude-code bootstrap 与第三方 `cc-switch-cli` 的 `install.sh`（`releases/latest` 未固定版本）。

建议固定版本 / commit 并校验 checksum。

### 13. 两套 CI 重复维护

[.cnb.yml](../.cnb.yml) 与 [.github/workflows/check.yml](../.github/workflows/check.yml) 检查项几乎一致，后续修改容易只改一边。

---

## 建议补充的测试

`cmd/main` 目前没有测试。建议补充：

- `format.mbt`：`json_escape` 控制字符、`now_ms` 量级、`format_ago` 各区间；
- `kind.mbt`：上文第 3 条列出的四类漏判；
- `resolve.mbt`：区间上限、越界下标；
- `args.mbt`：`-n abc`、缺值参数；
- `watch.mbt`：读失败后不再重复报错的回归测试。

## 附：复现方法

```bash
moon build --target native
M=_build/native/debug/build/cmd/main/main.exe

# 1 / 2 / 3 / 7 / 8
export MTUCK_DIR=/tmp/mtuck_repro && mkdir -p "$MTUCK_DIR"
printf 'hk-history\t1\n1700000000000\t1\t0\ttext\t0\ta\001\n1700000000000\t1\t0\ttext\t0\tauthorization: bearer abcdefghijklmnop\n1700000000000\t1\t0\ttext\t0\thttps://example.com/?token=abcdefghijklmnop\n' > "$MTUCK_DIR/history.tsv"
$M list            # 全部显示「刚刚」，密钥条目未打码
$M list --json     # 出现 "a\u000"，非法 JSON
$M rm 99           # 「已删除 0 条」+ 退出码 0

# 6
time $M rm 1-99999999
```
