# hk —— 终端剪贴板历史

> 系统剪贴板只记得最后一次复制。`hk` 让它变成一条可以回溯的时间线。

我复制完东西经常后悔：刚才那段 SQL 呢？那个 token 呢？`hk` 干一件很窄的事 ——
**后台盯着剪贴板，把每次复制记下来**，然后用一个命令翻回去。

```bash
hk watch                # 后台记录（Ctrl-C 退出）
hk list                 # 看历史
hk copy 3               # 把第 3 条写回剪贴板
```

（`hk` = 好看/吭哧/剪贴板，随你理解。）

## 为什么不是「又一个 clipboard 库」

MoonBit 生态里已经有几份成熟的剪贴板读写了：

| 包 | 下载量 | 形态 |
|---|---|---|
| `moonbit-community/proton_clipboard` | 25,634 | 异步 API，Win/macOS/Linux 三平台 |
| `justjavac/clipboard` | 6,185 | 同步 API |
| `sennenki/clipboard` | 1,435 | js + native |

读写剪贴板这件事**已经做完了**，`hk` 一行都没重写，直接依赖
`proton_clipboard`。`hk` 做的是它们都不做的那一层 —— **历史**：

- 去重（同一内容复制两次不会变两条，只累加 `hits`）
- 上限淘汰（默认 1000 条，固定条目永不淘汰）
- 类型识别（URL / JWT / DSN / 密钥赋值 / 私钥，敏感内容默认打码）
- 固定（`pin`）与检索（`-q`）、JSON 输出（`--json`）

## 安装与构建

```bash
moon add Tangbuting/hk
moon build --target native --release
```

需要 native 后端（`proton_clipboard` 只支持 native）。

Linux 还需要一个剪贴板工具在 `PATH` 上：`wl-copy`/`wl-paste`（Wayland）、
`xclip` 或 `xsel`（X11）。`hk` 直接沿用 `proton_clipboard` 的探测顺序，
缺工具时会明确告诉你缺什么。

## 命令

| 命令 | 作用 |
|---|---|
| `hk watch` | 持续监听剪贴板，每次变化立刻落盘 |
| `hk list` / `hk ls` | 列出历史（`-n` 条数、`-p` 只看固定、`-q` 搜索、`--json`） |
| `hk show <n>` | 打印第 n 条完整内容（敏感条目需要 `-f`） |
| `hk copy <n>` | 把第 n 条写回系统剪贴板 |
| `hk pin <n>` / `hk unpin <n>` | 固定 / 取消固定 |
| `hk rm <n>` | 删除（支持 `1,3`、`2-5`、`last`） |
| `hk clear` | 清空，默认保留固定条目（`-f` 连固定的也删） |
| `hk stats` | 条目数、固定数、疑似密钥数、类型分布、存储路径 |

编号就是 `hk list` 里显示的那个 `#n`，`0` 是最新一条。

```bash
$ hk list
  #0  刚刚      ×2  [text]    git status --short
  #1  2分钟前   ×1  [url]     https://mooncakes.io/docs/proton_clipboard
★ #2  5分钟前   ×1  [secret]  pass••••••••
```

## 数据存在哪

- 默认 `~/.local/share/hk/history.tsv`，`HK_DIR` 可以改目录。
- 格式是 TAB 分隔的行式文本，第一行 `hk-history\t1` 是版本头。

```
hk-history	1
1794723018	2	0	text	0	git status --short
1794722961	1	0	secret	1	password=hunter2
```

为什么不用 JSON：省一个依赖、能直接 `grep`、坏行跳过就完事。
写盘走 `.tmp` + `rename`，`Ctrl-C` 打断也不会留下半个文件。

**关于安全**：识别为 `secret` 的条目在 `list`/`watch` 里都会打码，
`show` 不带 `-f` 也只给打码结果。但**文件本身是明文的** —— 这是个
本地个人工具，没有主密码那一层。介意的话把 `HK_DIR` 指到加密盘。

## 项目结构

```
history/    纯逻辑：类型判定、条目模型、去重/淘汰、存储编解码（零 I/O 依赖，可单测）
watch/      事件源：轮询器 + 变更计数快路径（读取动作可注入，测试塞假实现）
platform/   平台小能力：macOS `NSPasteboard.changeCount` / Windows
            `GetClipboardSequenceNumber`，拿不到就返回 0 让上层退化成轮询
cmd/hk/     CLI：参数解析、落盘、格式化输出
```

依赖只有两个：`moonbit-community/proton_clipboard`（剪贴板读写）和官方
`moonbitlang/core/async`（异步 + 文件 + 进程）。剩下的都自己写。

## 几个踩过的坑

1. **`@env.now()` 返回的是微秒**，不是毫秒也不是纳秒。第一版时间戳
   集体小了一个数量级，`list` 里全部显示成"49 分钟前"。
2. **Linux 上 `xclip` 没有变更查询接口**，只能每轮读一遍文本比对。
   macOS/Windows 有原生 `changeCount`／序列号，`platform/` 里先探这个，
   探不到才退化成读文本。
3. **`moonbit-community/tui` 之外没有现成的输入框**，`hk watch` 就干脆
   不画界面，纯追加日志 —— 这也是它比 gui 版更适合塞进 tmux 面板的原因。

## 测试

```bash
moon test --target native
```

18 个测试，覆盖分类边界（URL / JWT / DSN / 多行密钥 / 打码）、
去重与淘汰、存储往返（含坏行与无表头老数据）、轮询状态机。

## 后续

- [ ] 图片剪贴板（PNG 落到 `~/.local/share/hk/images/`，历史里存路径）
- [ ] `hk watch --daemon` + `hk kill`（现在只能前台跑）
- [ ] 加密存储（ChaCha20 + 主密码，`mooncry` 现成）
- [ ] `hk pick` 的 TUI 选择器
