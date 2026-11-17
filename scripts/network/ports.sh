#!/bin/bash
set -euo pipefail

# 列出正在监听的端口以及持有它的进程。只读，不改任何东西。
# 端口不对、服务没起来、被别的进程占了 —— 先跑这个看一眼最快。

usage() {
    cat <<'USAGE'
用法: ports.sh [过滤串]

  无参数   列出全部监听端口
  过滤串   按端口号或字符串筛选，例如 ports.sh 8080 或 ports.sh docker

提示：非 root 时进程名一栏会是空的，要看是谁占用了端口就加 sudo。
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -*) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
esac

filter="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
    echo "提示: 当前不是 root，进程归属信息可能看不全" >&2
fi

if command -v ss >/dev/null 2>&1; then
    raw=$(ss -tulnp 2>/dev/null || ss -tuln 2>/dev/null)
elif command -v netstat >/dev/null 2>&1; then
    raw=$(netstat -tulnp 2>/dev/null || netstat -tuln 2>/dev/null)
else
    echo "需要 ss（iproute2）或 netstat（net-tools），本机都没找到" >&2
    exit 1
fi

if [ -z "${raw//[[:space:]]/}" ]; then
    echo "没有获取到任何监听套接字"
    exit 0
fi

printf '%s\n' "$raw" | head -n 1
rest=$(printf '%s\n' "$raw" | tail -n +2)

if [ -n "$filter" ]; then
    body=$(printf '%s\n' "$rest" | grep -i -- "$filter" || true)
    if [ -z "$body" ]; then
        echo "没有匹配「$filter」的监听端口"
        exit 0
    fi
else
    body="$rest"
fi

printf '%s\n' "$body"
echo
echo "共 $(printf '%s\n' "$body" | grep -c . || true) 条"
