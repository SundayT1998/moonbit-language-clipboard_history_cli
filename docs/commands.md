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
| `mtuck stats` | | 查看条目数、固定数、疑似密钥数、总字符 / 总字节、类型分布 |
| `mtuck help` | `-h` / `--help` | 帮助 |
| `mtuck version` | `--version` | 版本号 |

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
[{"index":0,"ts":1731600000000,"hits":3,"pinned":false,"kind":"url","secret":false,"text":"https://example.com"},
 {"index":1,"ts":1731599000000,"hits":1,"pinned":true,"kind":"text","secret":false,"text":"npm run build"}]

$ mtuck stats --json
{"total":42,"pinned":2,"secret":3,"chars":8123,"bytes":8300,"path":"/home/me/.local/share/mtuck/history.tsv","kinds":{"text":30,"url":9,"secret":3}}
```

### 退出码

| 码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `1` | 运行期错误（读写剪贴板失败、写历史失败等） |
| `2` | 用法错误（未知命令、下标看不懂、条目不存在） |

---

[← 返回 README](../README.mbt.md)
