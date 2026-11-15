# 贡献指南

欢迎提 Issue 和 PR。这个仓库是 MoonBit 项目，改动前后的基本要求如下。

## 环境

- [MoonBit CLI](https://www.moonbitlang.com/download/)（国内镜像：<https://www.moonbitlang.cn/download/>）；
- Linux 上如需真跑 `watch` / `copy`，另装 `wl-clipboard`（Wayland）或 `xclip` / `xsel`（X11）。

## 提交前自查

```bash
moon update
moon check --target native
moon fmt --check
moon test --target native
```

- 改了对外 API 时跑一次 `moon info`，检查 `*.mbti` 的 diff 是否符合预期；
- 没有剪贴板后端的环境请至少跑 `moon test`，并在 PR 里说明哪些路径没有实测。

仓库自带 pre-commit hook（只跑 `moon check`），启用方式：

```bash
git config core.hooksPath .githooks
```

## PR 约定

- 一个 PR 解决一个主题，标题用 `fix:` / `feat:` / `docs:` / `refactor:` 前缀；
- 描述里写清动机、改动点和验证方式（跑了哪些命令、有没有实测）；
- 涉及行为的改动请同步更新 `README.mbt.md` 与 `docs/` 下对应文档。

## 分支与远程

| 用途 | 地址 |
| --- | --- |
| 主仓库（CNB） | <https://cnb.cool/Tangbuting/moonbit-language/clipboard_history_cli> |
| GitHub 镜像 | <https://github.com/SundayT1998/moonbit-language-clipboard_history_cli> |

## 许可证

提交代码即表示同意以 [Apache-2.0](LICENSE) 授权。
