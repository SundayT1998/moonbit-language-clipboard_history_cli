# mtuck — 跨平台剪贴板历史工具

名字取自 **M**oonBit + **tuck**（把东西塞进兜里、收起来）——剪下来的片段随手收好，需要时再拿出来。
`mtuck` 是一个用 [MoonBit](https://www.moonbitlang.com/) 写的**终端剪贴板管理器**：
常驻后台记录你复制过的每一段内容，需要时按编号找回来、搜出来、再写回剪贴板。

- **跨平台**：macOS、Windows、Linux（Wayland / X11）一套代码，原生编译（`native` 后端）。
- **不离开终端**：`list` / `show` / `copy`，配合 shell 别名和管道即可接入任何工作流。
- **默认安全**：识别出的密钥、Token、带口令的连接串会自动打码，避免明文进历史文件。

```console
$ mtuck list
  #0  刚刚      ×3  [url]  https://github.com/moonbitlang/moon
★ #1  1 分钟前  ×1  [text]  cargo test --workspace
  #2  15 分钟前  ×1  [secret]  post••••••••
  #3  1 小时前   ×1  [text]  会议纪要：下周一对齐
```

## 安装

需要 [MoonBit CLI](https://www.moonbitlang.com/download/)（国内可用 [镜像](https://www.moonbitlang.cn/download/)）。
macOS / Windows 的剪贴板走系统原生接口，无需额外依赖；Linux 需要 `wl-clipboard`（Wayland）或 `xclip` / `xsel`（X11）：

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
| `mtuck stats` | | 条目数、固定数、疑似密钥数、总字符、类型分布 |
| `mtuck help` / `version` | `-h` / `--help`、`--version` | 帮助 / 版本号 |

`<n>` 是最新为 `0` 的编号，也支持 `last`、`1,3,5`、`2-5` 等写法。
完整选项、环境变量、`--json` 输出格式与退出码见 [docs/commands.md](docs/commands.md)。

更多文档（工作原理与存储格式、开发指南、开机自启）见 [docs/](docs/)。

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

[Apache-2.0](LICENSE)。内置的剪贴板能力来自
[proton_clipboard](https://mooncakes.io/docs/moonbit-community/proton_clipboard)。
