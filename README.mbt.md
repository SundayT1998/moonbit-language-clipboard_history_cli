# mtuck — 跨平台剪贴板历史工具

名字取自 **M**oonBit + **tuck**（把东西塞进兜里、收起来）——剪下来的片段随手收好，需要时再拿出来。
`mtuck` 是一个用 [MoonBit](https://www.moonbitlang.com/) 写的**终端剪贴板管理器**：
常驻后台记录你复制过的每一段内容，需要时按编号找回来、搜出来、再写回剪贴板。

- **跨平台**：macOS、Windows、Linux（Wayland / X11）一套代码，原生编译（`native` 后端），单二进制，不需要 Node / JVM 之类的语言运行时。
- **不离开终端**：`list` / `show` / `copy`，配合 shell 别名和管道即可接入任何工作流。
- **默认安全**：识别出的密钥、Token、带口令的连接串会自动打码，避免明文进历史文件。

```console
$ mtuck list
  #0  刚刚  ×3  [url]  https://github.com/moonbitlang/moon
  #1  1 分钟前  ×1  [text]  cargo test --workspace
★ #2  15 分钟前  ×1  [token]  ghp_••••••••
  #3  1 小时前  ×1  [text]  会议纪要：下周一对齐
```

## 安装

需要 [MoonBit CLI](https://www.moonbitlang.com/download/)（国内可用 [镜像](https://www.moonbitlang.cn/download/)）。
macOS / Windows 的剪贴板走系统原生接口，无需额外依赖；Linux 通过外部命令读写剪贴板，需要 `wl-clipboard`（Wayland）或 `xclip` / `xsel`（X11）之一：

```bash
# Debian / Ubuntu
sudo apt install xclip            # Wayland 用 wl-clipboard
# Fedora
sudo dnf install xclip
# Arch
sudo pacman -S xclip
```

从源码构建并安装：

```bash
git clone https://github.com/SundayT1998/moonbit-language-clipboard_history_cli.git
cd moonbit-language-clipboard_history_cli
moon update
moon build --release --target native
install -m 755 _build/native/release/build/cmd/main/main.exe ~/.local/bin/mtuck
```

确认 `~/.local/bin` 在 `PATH` 里，然后 `mtuck version` 验证安装。

### 运行环境与剪贴板后端

剪贴板读写由 `mtuck` 自己实现（`platform/clipboard_backend.c`），不依赖第三方剪贴板包：
Windows 与 macOS 直接调系统 API，Linux 走 `PATH` 里的 `wl-paste` / `xclip` / `xsel`。
各平台的输入来源不同，这决定了哪些命令在哪种环境里能用：

| 平台 | 读取 / 写入 | 变更检测 | 额外依赖 |
| --- | --- | --- | --- |
| macOS | AppKit `NSPasteboard` | `NSPasteboard.changeCount` | 无 |
| Windows | Win32 剪贴板 API | `GetClipboardSequenceNumber` | 无 |
| Linux（Wayland） | `wl-paste` / `wl-copy` | 读文本比对 | `wl-clipboard` |
| Linux（X11） | `xclip` 或 `xsel` | 读文本比对 | `xclip` 或 `xsel` |

剪贴板本身属于图形服务器，所以还需要一个**能连上的** X11（`DISPLAY`）或 Wayland（`WAYLAND_DISPLAY`）会话：

- **有图形服务器**（本地桌面、`Xvfb`、`ssh -X` 转发）：`watch` 与 `copy` 可用。
- **没有图形服务器**（纯 SSH 会话、无 X11 的容器、CI）：`watch` 与 `copy` 会报错退出并提示缺少后端；
  `list` / `show` / `pin` / `unpin` / `rm` / `clear` / `stats` 照常工作——它们只读写纯文本的 `history.tsv`，
  所以在远程机器上照样能查历史、也能被脚本直接消费。

`watch` 与 `copy` 启动前会先探一次后端：没图形会话、装了工具但 `DISPLAY` 连不上、
有会话但一个工具都没装，都会直接给出对应的处理建议并退出，
而不是每隔几百毫秒刷一行「读剪贴板失败」。后端不可用时只影响这两条命令，
`list` / `show` / `pin` / `rm` / `stats` 照常读写 `history.tsv`。

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
+ [url] https://mooncakes.io/docs/moonbitlang/x
+ [secret] ghp••••••••  (40 字符)
```

可以把 `watch` 交给系统托管，开机自动运行：见 [docs/autostart.md](docs/autostart.md)。

## 命令

| 命令 | 别名 | 作用 |
| --- | --- | --- |
| `mtuck watch` | | 持续监听剪贴板并写入历史，Ctrl-C 退出 |
| `mtuck list` | `ls` | 列出历史条目（`-n` 限制条数、`-q` 搜索、`-p` 只看固定） |
| `mtuck show <n>` | | 打印第 n 条的完整内容 |
| `mtuck copy <n>` | `cp` | 把第 n 条写回系统剪贴板 |
| `mtuck pin <n>` / `unpin <n>` | | 固定 / 取消固定条目 |
| `mtuck rm <n>` | `remove` | 删除条目 |
| `mtuck clear` | | 清空历史（默认保留固定条目，`-f` 全清） |
| `mtuck stats` | | 条目数、固定数、疑似密钥数、总字符 / 总字节 |
| `mtuck help` / `version` | `-h` / `--help`、`--version` | 帮助 / 版本号 |

`<n>` 是最新为 `0` 的编号，也支持 `last`、`1,3,5`、`2-5` 等写法。
需要剪贴板后端的只有 `watch` 和 `copy`，其余命令在没有图形服务器的环境里也能用。
完整选项、环境变量、`--json` 输出格式与退出码见 [docs/commands.md](docs/commands.md)。

更多文档（工作原理与存储格式、开发指南、开机自启）见 [docs/](docs/)，贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 路线图

- [x] 文本记录、去重合并、固定、上限淘汰
- [x] 密钥识别与默认打码
- [x] JSON 输出、下标区间批量操作
- [x] macOS / Windows 变更计数快路径
- [ ] **图片**：记录剪贴板图片（PNG 原图落盘 + 终端内预览），`copy` 时写回图片
- [ ] 模糊搜索 / 按类型筛选（`mtuck list --kind url`）
- [ ] 交互式选择界面（配合 fzf 或内置 TUI）
- [ ] 历史加密存储

## 许可

[Apache-2.0](LICENSE)。剪贴板读写是本仓库自己的实现，不依赖第三方剪贴板包。
