# 命令参考

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
| `mtuck stats` | | 查看条目数、固定数、疑似密钥数、总字符 / 总字节 |
| `mtuck help` | `-h` / `--help` | 帮助 |
| `mtuck version` | `--version` | 版本号 |

## 哪些命令需要剪贴板后端

只有 `watch` 和 `copy` 会碰系统剪贴板，其余命令只读写历史文件：

| 命令 | 需要图形服务器（X11 / Wayland） | 需要 Linux 外部命令 |
| --- | --- | --- |
| `watch` | 是 | 是（`wl-clipboard` 或 `xclip` / `xsel`） |
| `copy` | 是 | 同上 |
| `list` / `show` / `pin` / `unpin` / `rm` / `clear` / `stats` | 否 | 否 |

所以在纯 SSH 会话、无 X11 的容器、CI 里，`list` / `show` / `stats` 这些照常可用，
`watch` 会在启动时直接报错退出（而不是进入轮询后反复打印读取失败）。

## 条目编号

`<n>` 是 `list` 里显示的编号，**`0` 永远是最新一条**。也可以用：

- `last` / `latest` / `-1` —— 最新一条；
- `1,3,5` —— 多条；
- `2-5` —— 区间。

所以 `mtuck rm 0-4` 删最新五条，`mtuck pin 1,3,7` 一次固定三条。

## 选项

| 选项 | 适用命令 | 说明 |
| --- | --- | --- |
| `-n, --limit <k>` | `list` | 最多显示 k 条（默认 20，`0` 表示全部） |
| `-i, --interval <ms>` | `watch` | 轮询间隔毫秒（1–60000，默认 400；`-n` 在 `watch` 下不生效） |
| `-f, --full` | `list` / `show` | 显示完整内容：不截断、不给密钥打码 |
| `-f` | `clear` | 连固定条目一起删 |
| `-p, --pinned` | `list` | 只看固定条目 |
| `-q, --query <s>` | `list` | 子串过滤（区分大小写） |
| `--json` | `list` / `stats` | 输出 JSON，便于脚本消费 |

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MTUCK_DIR` | `~/.local/share/mtuck` | 历史文件所在目录 |
| `HOME` | — | 未设置 `MTUCK_DIR` 时用来推导默认目录 |

## 输出格式

### `mtuck list`

```
★ 标  编号  相对时间  ×复制次数  [类型]  预览
★ #1  2 分钟前  ×3  [url]  https://example.com
```

密钥类条目在预览里会被打码（`--json` 输出同样打码，并带 `redacted` 字段标记）；`-f` 显示原文。
旧版本写入的条目在 `list` 时会按当前规则重新判定，避免漏判的密钥继续明文显示。

`stats` 同时报“总字符”和“总字节”：前者是字符数（与 `text.length()` 一致），
后者是 UTF-8 编码后的字节数，与单条 256 KiB 上限、`--json` 里的 `bytes` 同一口径。

### `--json`

```console
$ mtuck list --json -n 2
[{"index":0,"ts":1731600000000,"hits":3,"pinned":false,"kind":"url","secret":false,"redacted":false,"text":"https://example.com"},{"index":1,"ts":1731599000000,"hits":1,"pinned":true,"kind":"text","secret":false,"redacted":false,"text":"npm run build"}]

$ mtuck stats --json
{"total":42,"pinned":2,"secret":3,"chars":8123,"bytes":8300,"path":"/home/me/.local/share/mtuck/history.tsv","kinds":{"text":30,"url":9,"token":3}}
```

`list --json` 是一个**单行**数组（没有换行、没有缩进），每个元素都带 `redacted`：
密钥类条目在默认输出里被打了码，这个字段为 `true`；配合 `-f` 时输出原文，字段为 `false`。
`stats --json` 里的 `kinds` 直接按历史文件里记录的标签计数，键名就是 `kind` 的取值
（`text`、`url`、`dsn`、`jwt`、`secret`、`empty`）。`list` 会先按当前规则重新判定标签，
`stats` 不会——两者对旧版本写入的条目可能出现不同的 `kind` 统计。

### 退出码

| 码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `1` | 运行期错误（读写剪贴板失败、没有可用的剪贴板后端、写历史失败等） |
| `2` | 用法错误（未知命令、未知选项、某个命令不支持的选项、下标看不懂、条目不存在） |

`show` / `pin` / `unpin` / `rm` 只要求其中一个编号存在即可执行；`show` 和 `pin` / `rm` 一样，
只要有编号越界就以 `2` 结束。

---

[← 返回 README](../README.mbt.md)
