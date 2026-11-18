# 工作原理

## 记录流程

```
 系统剪贴板 ──读取──> Watcher ──变化?──> History.push ──落盘──> history.tsv
                        │                   │
                 macOS/Windows 用变更计数  去重合并 / 类型判定 / 打码 / 上限淘汰
                 Linux 读文本比对
```

- **事件源**：`watch` 包负责轮询。macOS 的 `NSPasteboard.changeCount`、Windows 的
  `GetClipboardSequenceNumber` 提供轻量的"剪贴板变了没"计数（见
  [platform/stub.c](../platform/stub.c)），Linux 没有这类接口，直接读文本比对。
- **读写剪贴板**：通过 [`moonbit-community/proton_clipboard`](https://mooncakes.io/docs/moonbit-community/proton_clipboard)，
  Windows / macOS 原生调用，Linux 调用 `wl-paste`/`xclip`/`xsel`。
  本仓库不含任何剪贴板协议实现，Linux 的能力完全由这些外部命令提供。
- **后端探测**：`watch` 启动时先确认剪贴板后端可达（见下节），不可达直接退出，不进入轮询。
- **持久化**：每次有变化立刻"写临时文件 + rename"落盘，Ctrl-C、崩溃都不会留下半个文件。
  轮询和落盘是两个任务：`watch_loop` 读剪贴板、改写内存，消费者任务按序写盘，
  落盘期间轮询不会被卡住，连续复制的中间内容不会漏掉；队列（`Blocking(1)`）
  满时跳过这一次交付，下一次交付最新内存状态，退出后的整体落盘兜底。

## 历史模型

- 头部永远是最新一条，编号即位置。
- **去重**：新内容与已有未固定条目相同时合并为一条，`hits` 加一，并提到最前；
  合并后的 `ts` 仍是**首次**复制的时间（`list` 里的“多久以前”指首次出现）。
- **上限**：默认 1000 条（`history/store.mbt` 中的 `max_entries`），超出后从最旧的
  **未固定**条目开始丢。
- **固定**：`pin` 过的条目永不淘汰、也不参与合并——适合放常用命令、模板。
- **单条上限**：256 KiB（按 UTF-8 编码后的真实字节数），超过直接忽略，`watch` 会提示。

## 内容类型与保密判定

`mtuck` 会在写入时给每条打上类型标签（`mtuck stats` 会统计分布）：

| 类型 | 判定规则 | 默认是否打码 |
| --- | --- | --- |
| `url` | `http(s)://`、`ftp://`、`file://`、`mailto:` 等 | 否 |
| `dsn` | 其他 `scheme://…` 形式，如 `postgres://host/db`（带 `user:pass@` 的归到 `secret`） | 否 |
| `jwt` | `eyJ…` 开头且含三个 `.` 段 | 是 |
| `secret` | 私钥块；`password=`/`api_key=`/`token=` 等赋值；`authorization` / `bearer` 头；`sk-`/`ghp_`/`AKIA` 等裸密钥前缀；任意 `scheme://user:pass@host` | 是 |
| `text` | 其他 | 否 |
| `empty` | 空内容 | 否 |

`scheme://user:pass@host` 这类带账号密码的连接串不算 `dsn`，一律归到 `secret` 并打码；
只是“非 http 的 scheme”并不代表安全，凭据写在查询参数里（`?token=`）同样会命中。

打码规则：保留前 4 个字符，其余替换为 `•`（最多 8 个）。
`show <n> -f` 或 `list -f` 才输出原文。

## 存储格式

纯文本 TSV，文件头 `mtuck-history	1`，每行六列：

```
ts	hits	pinned	kind	is_secret	text
```

`ts` 是**首次**复制该内容的毫秒时间戳（去重合并只加 `hits`，不改 `ts`）。其中 `text` 里的换行、制表、回车、反斜杠会被转义。选它而不是 JSON 的原因：
不需要数据库或第三方序列化库、`grep`/`diff` 友好、单行损坏可以跳过而不影响其余数据。

文件是**明文**的：目录权限 0700、`history.tsv` 权限 0600，只有当前用户可读。
识别为 `secret` 的条目同样以原文落盘（只是显示时打码），
所以分享目录、备份或同步前请留意。

## 平台实现说明

| 平台 | 变更检测 | 读写剪贴板 | 额外依赖 |
| --- | --- | --- | --- |
| macOS | `NSPasteboard.changeCount`（C stub） | AppKit `NSPasteboard` | 无 |
| Windows | `GetClipboardSequenceNumber`（C stub） | Win32 剪贴板 API | 无 |
| Linux（Wayland） | 读文本比对 | `wl-paste` / `wl-copy` | `wl-clipboard` |
| Linux（X11） | 读文本比对 | `xclip` / `xsel` | `xclip` 或 `xsel` |

`platform/stub.c` 只负责「剪贴板变了没」这个计数快路径，缺失（返回 `0`）时自动退化为读文本比对，
与读写剪贴板本身无关。

## 剪贴板后端与可用性边界

剪贴板是图形服务器的能力，不是进程自己的状态。因此「有没有桌面」并不关键，
**有没有能连上的图形服务器**才是关键：`xclip` / `wl-paste` 只需要 `XOpenDisplay` / 连 Wayland socket，
不需要窗口管理器，也不需要显示器。

| 环境 | `watch` / `copy` | 其余命令 |
| --- | --- | --- |
| 本地桌面（X11 或 Wayland） | 可用 | 可用 |
| 无桌面但有图形服务器（Xvfb、`ssh -X`） | 可用，但剪贴板内容取决于有没有 owner | 可用 |
| 无图形服务器（纯 SSH、无 X11 的容器、CI） | 报错退出 | 可用 |

`list` / `show` / `pin` / `unpin` / `rm` / `clear` / `stats` 只读写 `history.tsv`，
所以在 SSH 与容器里对同一份历史做检索与管理是成立的；这也让 `moon test` 与 CI 不依赖任何剪贴板后端。

上游 `proton_clipboard` 在 Linux 上只按 `PATH` 探测 `wl-paste` / `xclip` / `xsel` 是否存在，
**不探测能否连上服务器**，所以「装了 `xclip` 但没有 X server」会被误判为后端可用，
读出来是空内容或 `Failed to read clipboard`。`mtuck` 在 `watch` 启动前额外检查
`DISPLAY` / `WAYLAND_DISPLAY` 与实际 socket，连不上就直接给出人话报错，
避免用户从一行笼统的读取失败里去猜根因。

---

[← 返回 README](../README.mbt.md)
