# 开发指南

## 常用命令

```bash
moon check --target native   # 类型检查
moon test --target native    # 跑测试（当前 115 个）
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

## 测试策略

`history` 与 `watch` 都是纯逻辑，用假读取器与构造数据覆盖；
平台相关的原生一栏只有编译期的保证。

---

[← 返回 README](../README.mbt.md)
