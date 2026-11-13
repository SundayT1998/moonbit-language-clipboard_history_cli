# mtuck — 跨平台剪贴板历史工具

名字取自 **M**oonBit + **tuck**（把东西塞进兜里、收起来）——剪下来的片段随手收好，需要时再拿出来。
`mtuck` 是一个用 [MoonBit](https://www.moonbitlang.com/) 写的**终端剪贴板管理器**：
常驻后台记录你复制过的每一段内容，需要时按编号找回来、搜出来、再写回剪贴板。

- **跨平台**：macOS、Windows、Linux（Wayland / X11）一套代码，原生编译（`native` 后端）。
- **文本+图片**：记录任意文本（多行、代码、URL、密钥……）以及剪贴板里的图片。
  *（图片支持是 1.1 目标，见 [路线图](#路线图)；0.1 版本记录文本。）*
- **不离开终端**：`list` / `show` / `copy`，配合 shell 别名和管道即可接入任何工作流。
- **默认安全**：识别出的密钥、Token、带口令的连接串会自动打码，避免明文进历史文件。

```console
$ mtuck list
  #0  刚刚      ×3  [url]  https://github.com/moonbitlang/moon
★ #1  1 分钟前  ×1  [text]  cargo test --workspace
  #2  15 分钟前  ×1  [secret]  post••••••••
  #3  1 小时前   ×1  [text]  会议纪要：下周一对齐
```

---

## 为什么需要它

系统剪贴板只有一格，下一次复制就覆盖上一次。`mtuck` 把剪贴板当成一条**可回溯的时间线**：

| 痛点 | `mtuck` 的做法 |
| --- | --- |
| 复制了 A，复制 B 之后 A 丢了 | `watch` 常驻记录，`list` 随时查看 |
| 想找十分钟前复制的那条命令 | 按编号、`-q` 子串搜索、按类型/固定筛选 |
| 复制内容太多，历史文件越滚越大 | 去重合并、上限淘汰、固定条目永不过期 |
| 复制了密码，担心被明文保存 | 自动识别为 `secret` 并打码，`-f` 才看原文 |
| 想在脚本里用历史内容 | `--json` 输出、`copy` 写回、管道友好的纯文本 |

---

## 安装

### 前置条件

- [MoonBit CLI](https://www.moonbitlang.com/download/)：国内用 `https://www.moonbitlang.cn/download/`，国外用 `https://www.moonbitlang.com/download/`。
- 系统剪贴板后端：

  | 平台 | 需要的东西 |
  | --- | --- |
  | macOS | 无（走 AppKit `NSPasteboard`） |
  | Windows | 无（走 Win32 剪贴板 API） |
  | Linux / Wayland | `wl-clipboard`（`wl-copy` / `wl-paste`） |
  | Linux / X11 | `xclip` 或 `xsel` |

  ```bash
  # Debian / Ubuntu
  sudo apt install xclip            # 或 wl-clipboard
  # Fedora
  sudo dnf install xclip            # 或 wl-clipboard
  # Arch
  sudo pacman -S xclip              # 或 wl-clipboard
  ```

### 从源码构建

```bash
git clone https://github.com/SundayT1998/clipboard_history_cli.git
cd clipboard_history_cli
moon update
moon build --release --target native
```

`moon.mod` 里的模块名仍是 `clipboard_history_cli`；产物是 `main.exe`，安装时改成 `mtuck` 放进 `PATH`：

```bash
install -m 755 _build/native/release/build/cmd/main/main.exe ~/.local/bin/mtuck
```

---

## 快速上手

```bash
mtuck watch          # 终端 1：开始记录（保持运行，Ctrl-C 退出）
# …… 正常复制粘贴 ……

mtuck list           # 终端 2：看看记了什么
mtuck show 0         # 看最新一条的完整内容
mtuck copy 3         # 把第 3 条写回系统剪贴板，然后直接 Ctrl-V
mtuck list -q moon   # 按子串搜索
```

`watch` 期间每记录一条都会立刻落盘并打印一行预览：

```console
监听剪贴板中（每 1000ms 检查一次，Ctrl-C 退出）
已有 12 条历史
+ [text] git log --oneline -20
+ [url] https://mooncakes.io/docs/moonbit-community/proton_clipboard
+ [secret] ghp••••••••  (40 字符)
```

---

## 命令一览

| 命令 | 别名 | 作用 |
| --- | --- | --- |
| `mtuck watch` | | 持续监听剪贴板并写入历史，Ctrl-C 退出 |
| `mtuck list` | `ls` | 列出历史条目 |
| `mtuck show <n>` | | 打印第 n 条的完整内容 |
| `mtuck copy <n>` | `cp` | 把第 n 条写回系统剪贴板 |
| `mtuck pin <n>` | | 固定条目：不被上限淘汰、不参与去重合并 |
| `mtuck unpin <n>` | | 取消固定 |
| `mtuck rm <n>` | `remove` | 删除条目 |
| `mtuck clear` | | 清空历史（默认保留固定条目） |
| `mtuck stats` | | 查看条目数、固定数、疑似密钥数、总字符、类型分布 |
| `mtuck help` | `-h` / `--help` | 帮助 |
| `mtuck version` | `--version` | 版本号 |

`<n>` 是 `list` 里显示的编号，**`0` 永远是最新一条**。也可以用：

- `last` / `latest` / `-1` —— 最新一条；
- `1,3,5` —— 多条；
- `2-5` —— 区间。

所以 `mtuck rm 0-4` 删最新五条，`mtuck pin 1,3,7` 一次固定三条。

### 选项

| 选项 | 适用命令 | 说明 |
| --- | --- | --- |
| `-n, --limit <k>` | `list` | 最多显示 k 条（默认 20，`0` 表示全部） |
| `-i, --interval <ms>` | `watch` | 轮询间隔毫秒（1–60000，默认 400；`-n` 在 `watch` 下不生效） |
| `-f, --full` | `list` / `show` | 显示完整内容：不截断、不给密钥打码 |
| `-f` | `clear` | 连固定条目一起删 |
| `-p, --pinned` | `list` | 只看固定条目 |
| `-q, --query <s>` | `list` | 子串过滤（区分大小写） |
| `--json` | `list` / `stats` | 输出 JSON，便于脚本消费 |

### 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MTUCK_DIR` | `~/.local/share/mtuck` | 历史文件所在目录 |
| `HOME` | — | 未设置 `MTUCK_DIR` 时用来推导默认目录 |

---

## 输出格式

### `mtuck list`

```
★ 标  编号  相对时间  ×复制次数  [类型]  预览
★ #1  2 分钟前  ×3  [url]  https://example.com
```

密钥类条目在预览里会被打码（`--json` 输出同样打码，并带 `redacted` 字段标记）；`-f` 显示原文。
旧版本写入的条目在 `list` 时会按当前规则重新判定，避免漏判的密钥继续明文显示。

### `--json`

```console
$ mtuck list --json -n 2
[{"index":0,"ts":1731600000000,"hits":3,"pinned":false,"kind":"url","secret":false,"text":"https://example.com"},
 {"index":1,"ts":1731599000000,"hits":1,"pinned":true,"kind":"text","secret":false,"text":"npm run build"}]

$ mtuck stats --json
{"total":42,"pinned":2,"secret":3,"chars":8123,"path":"/home/me/.local/share/mtuck/history.tsv","kinds":{"text":30,"url":9,"secret":3}}
```

配合 `jq`：

```bash
mtuck list --json -n 0 | jq -r '.[] | select(.kind=="url") | .text'
mtuck list --json -n 0 | jq -r '.[] | select(.pinned) | .text'
# 按当前剪贴板内容反查来源
mtuck list -q "$(xclip -o -selection clipboard)"
```

### 退出码

| 码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `1` | 运行期错误（读写剪贴板失败、写历史失败等） |
| `2` | 用法错误（未知命令、下标看不懂、条目不存在） |

---

## 工作原理

### 记录流程

```
 系统剪贴板 ──读取──> Watcher ──变化?──> History.push ──落盘──> history.tsv
                        │                   │
                 macOS/Windows 用变更计数  去重合并 / 类型判定 / 打码 / 上限淘汰
                 Linux 读文本比对
```

- **事件源**：`watch` 包负责轮询。macOS 的 `NSPasteboard.changeCount`、Windows 的
  `GetClipboardSequenceNumber` 提供轻量的"剪贴板变了没"计数（见
  [platform/stub.c](platform/stub.c)），Linux 没有这类接口，直接读文本比对。
- **读写剪贴板**：通过 [`moonbit-community/proton_clipboard`](https://mooncakes.io/docs/moonbit-community/proton_clipboard)，
  Windows / macOS 原生调用，Linux 调用 `wl-paste`/`xclip`/`xsel`。
- **持久化**：每次有变化立刻"写临时文件 + rename"落盘，Ctrl-C、崩溃都不会留下半个文件。

### 历史模型

- 头部永远是最新一条，编号即位置。
- **去重**：新内容与已有未固定条目相同时合并为一条，`hits` 加一，并提到最前。
- **上限**：默认 1000 条（`history/store.mbt` 中的 `max_entries`），超出后从最旧的
  **未固定**条目开始丢。
- **固定**：`pin` 过的条目永不淘汰、也不参与合并——适合放常用命令、模板。
- **单条上限**：256 KiB（按 UTF-8 估算），超过直接忽略，`watch` 会提示。

### 内容类型与保密判定

`mtuck` 会在写入时给每条打上类型标签（`mtuck stats` 会统计分布）：

| 类型 | 判定规则 | 默认是否打码 |
| --- | --- | --- |
| `url` | `http(s)://`、`ftp://`、`file://`、`mailto:` 等 | 否 |
| `dsn` | 其他 `scheme://…` 形式，如 `postgres://host/db` | 否 |
| `jwt` | `eyJ…` 开头且含三个 `.` 段 | 是 |
| `secret` | 私钥块；`password=`/`api_key=`/`token=` 等赋值；`authorization` / `bearer` 头；`sk-`/`ghp_`/`AKIA` 等裸密钥前缀；任意 `scheme://user:pass@host` | 是 |
| `text` | 其他 | 否 |
| `empty` | 空内容 | 否 |

打码规则：保留前 4 个字符，其余替换为 `•`（最多 8 个）。
`show <n> -f` 或 `list -f` 才输出原文。

### 存储格式

纯文本 TSV，文件头 `mtuck-history	1`，每行六列：

```
ts	hits	pinned	kind	is_secret	text
```

其中 `text` 里的换行、制表、回车、反斜杠会被转义。选它而不是 JSON 的原因：
零额外依赖、`grep`/`diff` 友好、单行损坏可以跳过而不影响其余数据。

---

## 常见用法

### 终端里随时翻历史

```bash
alias mt='mtuck list -n 0'
alias mtls='mtuck list'
```

### 只找 URL

```bash
mtuck list -n 0 --json | jq -r '.[] | select(.kind=="url") | "\(.index)\t\(.text)"'
```

### 把常用片段钉住

```bash
mtuck list -q "kubectl" -n 1        # 找到那条
mtuck pin 0                          # 固定它
mtuck list -p                        # 以后只看固定条目
```

### 定时清理，但保留固定的

```bash
mtuck clear                          # 保留固定条目
mtuck clear -f                       # 全清
```

### 在脚本里复用

```bash
# 把最新一条复制内容输出到标准输出
mtuck show last

# 拿来当作另一个命令的参数
git commit -m "$(mtuck show last)"
```

### 开机自启 `watch`

<details>
<summary>macOS（launchd）</summary>

`~/Library/LaunchAgents/dev.mtuck.watch.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.mtuck.watch</string>
  <key>ProgramArguments</key>
  <array><string>/Users/me/.local/bin/mtuck</string><string>watch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/mtuck-watch.log</string>
  <key>StandardErrorPath</key><string>/tmp/mtuck-watch.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/dev.mtuck.watch.plist
```

</details>

<details>
<summary>Linux（systemd --user）</summary>

`~/.config/systemd/user/mtuck-watch.service`：

```ini
[Unit]
Description=mtuck clipboard history watcher

[Service]
ExecStart=%h/.local/bin/mtuck watch
Restart=always
Environment=MTUCK_DIR=%h/.local/share/mtuck

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now mtuck-watch
```

</details>

<details>
<summary>Windows（任务计划程序）</summary>

```powershell
schtasks /Create /SC ONLOGON /TN "mtuck watch" /TR "C:\tools\mtuck.exe watch" /RL LIMITED
```

</details>

---

## 项目结构

```
.
├── cmd/main/        # 可执行入口：参数解析、各子命令、读写历史文件
│   ├── args.mbt     #   命令行解析与 help
│   ├── commands.mbt #   watch/list/show/copy/pin/rm/clear/stats
│   ├── resolve.mbt  #   "last" / "1,3" / "2-5" 下标解析
│   ├── format.mbt   #   相对时间、JSON 转义、毫秒时间戳
│   └── store_io.mbt #   历史文件路径与安全落盘
├── history/         # 纯逻辑，无 I/O：可任意后端测试
│   ├── store.mbt    #   History 模型：去重、固定、上限淘汰
│   ├── kind.mbt     #   类型判定与打码
│   └── codec.mbt    #   TSV 编解码
├── watch/           # 事件源：剪贴板轮询器 + 变更计数快路径
└── platform/        # 平台小能力：macOS/Windows 原生变更计数（C stub）
```

依赖关系单向：`cmd/main` → `watch` / `history`，`watch` → `platform`；`history` 不依赖任何 I/O。

---

## 开发

```bash
moon check --target native   # 类型检查
moon test --target native    # 跑测试（当前 18 个）
moon fmt                     # 格式化
moon info                    # 更新 .mbti 接口文件，检查对外 API 是否变化
```

提交前建议启用仓库自带的 hook：

```bash
git config core.hooksPath .githooks   # 每次 commit 自动 moon check
```

CI 在 [`.github/workflows/check.yml`](.github/workflows/check.yml) 与 [`.cnb.yml`](.cnb.yml)：
`moon check` → `moon fmt --check` → `moon test`。

测试策略：`history` 与 `watch` 都是纯逻辑，用假读取器与构造数据覆盖；
平台相关的原生一栏只有编译期的保证。

---

## 路线图

- [x] 文本记录、去重合并、固定、上限淘汰
- [x] 密钥识别与默认打码
- [x] JSON 输出、下标区间批量操作
- [x] macOS / Windows 变更计数快路径
- [ ] **图片**：记录剪贴板图片（PNG 原图落盘 + 终端内预览），`copy` 时写回图片
- [ ] 模糊搜索 / 按类型筛选（`mtuck list --kind url`）
- [ ] 交互式选择界面（配合 fzf 或内置 TUI）
- [ ] 历史加密存储

---

## 已知限制

- 0.1 版本只处理**文本**；图片与富文本（HTML/RTF）尚未记录。
- Linux 下必须依赖外部工具（`wl-clipboard` / `xclip` / `xsel`），没有工具时
  `watch` 会报错，`copy` 会失败。
- 某些应用的复制（如部分密码管理器）会主动清空剪贴板，这类行为会被记录为空并不入库。
- `-q` 搜索是区分大小写的子串匹配，不支持正则。

---

## 许可

[Apache-2.0](LICENSE)。内置的剪贴板能力来自
[proton_clipboard](https://mooncakes.io/docs/moonbit-community/proton_clipboard)。
