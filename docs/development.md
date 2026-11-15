# 开发指南

## 常用命令

```bash
moon check --target native   # 类型检查
moon test --target native    # 跑测试（最后一行的 Total tests 是当前数量）
moon fmt                     # 格式化
moon info                    # 更新 .mbti 接口文件，检查对外 API 是否变化
```

提交前建议启用仓库自带的 hook：

```bash
git config core.hooksPath .githooks   # 每次 commit 自动 moon check
```

CI 在 [`.github/workflows/check.yml`](../.github/workflows/check.yml) 与 [`.cnb.yml`](../.cnb.yml)：
`moon check` → `moon fmt --check` → `moon test`。

## 项目结构

```
.
├── cmd/main/            # 可执行入口：参数解析、各子命令、读写历史文件
│   ├── main.mbt         #   入口与命令分发
│   ├── args.mbt         #   命令行解析与 help
│   ├── resolve.mbt      #   "last" / "1,3" / "2-5" 下标解析
│   ├── store_io.mbt     #   历史文件路径与安全落盘
│   ├── list_cmd.mbt     #   list：过滤、截断、底部提示、行渲染
│   ├── watch_cmd.mbt    #   watch（轮询 / 落盘双任务）与 copy
│   ├── record_cmd.mbt   #   show / pin / unpin / rm / clear
│   ├── stats_cmd.mbt    #   stats：规模统计与类型分布
│   ├── time_fmt.mbt     #   相对时间、毫秒时间戳
│   ├── json.mbt         #   JSON 转义与 list / stats 的 JSON 输出
│   └── test_fixtures_wbtest.mbt  # 多个测试文件共用的夹具
├── history/             # 纯逻辑，无 I/O：可任意后端测试
│   ├── store.mbt        #   History 模型：去重、固定、上限淘汰、重判密钥
│   ├── kind.mbt         #   类型判定与打码
│   └── codec.mbt        #   TSV 编解码
├── watch/           # 事件源：剪贴板轮询器 + 变更计数快路径
└── platform/        # 平台小能力：macOS/Windows 原生变更计数（C stub）
```

依赖关系单向：`cmd/main` → `watch` / `history`，`watch` → `platform`；`history` 不依赖任何 I/O。

`cmd/main` 是唯一的可执行包，不能再往下拆子包，所以按命令分文件：
新增一个子命令就加一个 `<命令>_cmd.mbt` 和配套的 `<命令>_cmd_wbtest.mbt`。
能在 `history` 里表达成模型行为的逻辑（如 `History::reclassify`）就下沉过去，
`cmd/main` 只留 I/O 和终端展示。

## 测试策略

`history` 与 `watch` 都是纯逻辑，用假读取器与构造数据覆盖；
平台相关的原生一栏只有编译期的保证。
`cmd/main` 的测试按文件对应：夹具放 `test_fixtures_wbtest.mbt`，
跨文件共用的历史样本统一从那里取。

---

[← 返回 README](../README.mbt.md)
