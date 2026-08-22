#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# 1️⃣ 读取可选的 .env 文件（如果存在）
# -------------------------------------------------
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
fi

# -------------------------------------------------
# 2️⃣ 启动 opencode（OpenAI‑compatible 代理）
# -------------------------------------------------
# 本机的 Ollama 默认监听 127.0.0.1:11434
# 我们把它包装成 http://127.0.0.1:8085/v1

echo "=== 启动 opencode 代理 (本机) ==="
nohup opencode serve --base-url http://127.0.0.1:11434 --port 8085 \
    > opencode.log 2>&1 &
OPENCODE_PID=$!

echo "opencode PID=$OPENCODE_PID"

# -------------------------------------------------
# 3️⃣ 启动 napcat（QQ OneBot）
# -------------------------------------------------
# 使用官方容器来启动 napcat（仅依赖 Docker）

echo "=== 启动 NapCat (QQ OneBot) ==="
mkdir -p napcat
# 如已有本机配置则拷贝进去，否则容器首次运行会生成默认配置
if [[ -d ~/napcat-config ]]; then
    cp -r ~/napcat-config napcat/.config
else
    # 生成默认配置（一次性）
    docker run --rm mlikiowa/napcat-docker:latest cp -r /app/.config "$PWD/napcat/.config"
fi

docker run -d --name napcat_local \
    -v "$PWD/napcat/.config:/app/.config" \
    -e NAPCAT_UID=${NAPCAT_UID:-1000} -e NAPCAT_GID=${NAPCAT_GID:-1000} \
    -p 6099:6099 -p 3000:3000 -p 3001:3001 \
    mlikiowa/napcat-docker:latest
NAPCAT_CONTAINER=napcat_local

echo "napcat container=$NAPCAT_CONTAINER"

# -------------------------------------------------
# 4️⃣ 启动 AstrBot 主体
# -------------------------------------------------
# 确保插件已拷贝到运行时目录
mkdir -p data
if [[ ! -d data/plugins/astrbot_plugin_zhaoqingyu ]]; then
    cp -r plugins/astrbot_plugin_zhaoqingyu data/plugins/
fi

# 使用本机 opencode 代理的 URL
export OPENCODE_BASE_URL="http://127.0.0.1:8085/v1"

# AstrBot 二进制默认放在 $HOME/bin/astrbot（如果已经下载）
if [[ ! -x ~/bin/astrbot ]]; then
    echo "警告：未检测到 ~/bin/astrbot 二进制，请自行下载并放置。"
    echo "下载示例："
    echo "  mkdir -p ~/bin && cd ~/bin && wget -O astrbot https://github.com/soulter/astrbot/releases/download/v4.19.0/astrbot-linux-amd64 && chmod +x astrbot"
    exit 1
fi

echo "=== 启动 AstrBot ==="
~/bin/astrbot \
    --data-dir "$(pwd)/data" \
    --plugin-dir "$(pwd)/data/plugins" \
    --config-dir "$HOME/.zhaoqingyu" \
    --port 6185

# -------------------------------------------------
# 5️⃣ 退出清理（Ctrl‑C 时自动调用）
# -------------------------------------------------
cleanup() {
    echo "=== 正在关闭服务 ==="
    kill "$OPENCODE_PID" 2>/dev/null || true
    docker stop "$NAPCAT_CONTAINER" && docker rm "$NAPCAT_CONTAINER" || true
}
trap cleanup EXIT
