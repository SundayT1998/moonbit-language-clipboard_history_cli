# .ide/Dockerfile

FROM cnbcool/default-dev-env:latest

# 基础镜像用 tag 固定，cc-switch-cli 用固定版本 + sha256 校验：
# 不从 `releases/latest` 执行下载来的脚本，避免上游发版悄悄进入构建。
ARG CC_SWITCH_VERSION=v5.11.3
ARG CC_SWITCH_SHA256=c033fba9848e2962a16ecc6859053adb26fd62c7c035c6e1179c84c8a3581eea

RUN apt-get update && apt-get install -y gcc

RUN curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash

# claude-code 的 bootstrap.sh 只从主域名下载，版本由一个固定路径的文件给出，
# 无法把版本或校验和固定在 URL 里；这里按官方方式直接执行。
RUN curl -fsSL https://downloads.claude.ai/claude-code-releases/bootstrap.sh | bash

# cc-switch-cli：下载固定版本的归档，校验 sha256 后从归档安装（不再执行 install.sh）。
RUN set -eux; \
    mkdir -p /tmp/cc-switch; \
    url="https://github.com/SaladDay/cc-switch-cli/releases/download/${CC_SWITCH_VERSION}/cc-switch-cli-${CC_SWITCH_VERSION}-linux-x64.tar.gz"; \
    curl -fsSL -o /tmp/cc-switch/cc-switch.tar.gz "$url"; \
    echo "${CC_SWITCH_SHA256}  /tmp/cc-switch/cc-switch.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/cc-switch/cc-switch.tar.gz -C /tmp/cc-switch; \
    install -m 0755 /tmp/cc-switch/cc-switch /usr/local/bin/cc-switch; \
    rm -rf /tmp/cc-switch

ENV PATH="$PATH:/root/.local/bin:/root/.moon/bin"

RUN code-server --install-extension tamasfe.even-better-toml \
     && code-server --install-extension usernamehw.errorlens \
     && code-server --install-extension chanhx.crabviz \
     && code-server --install-extension moonbit.moonbit-lang \
     && code-server --install-extension Anthropic.claude-code
