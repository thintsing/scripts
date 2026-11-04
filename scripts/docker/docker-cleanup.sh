#!/bin/bash
set -euo pipefail

# Docker 无用数据清理。默认 dry-run 只报告，加 --apply 才真正删除。
# 依赖：docker CLI + 守护进程可用（当前用户能访问 docker.sock）。

usage() {
    cat <<'USAGE'
用法: docker-cleanup.sh [--apply] [--all-images]

  默认          显示 docker system df 与各待清理对象数量，不做任何删除
  --apply       执行清理：已停止的容器、悬空镜像、未使用的自定义网络、构建缓存
  --all-images  配合 --apply，额外删除所有当前没有任何容器引用的镜像（不只是悬空）

注意：--apply 会删除处于 exited 状态的容器。如果你有靠 stop 保留数据、
以后还要 docker start 起来的容器，不要直接加 --apply，先看清数量。
USAGE
}

apply=0
all_images=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --apply) apply=1 ;;
        --all-images) all_images=1 ;;
        *) echo "未知参数: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

command -v docker >/dev/null 2>&1 || { echo "未找到 docker 命令" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker 守护进程不可用，或当前用户无权访问 docker.sock" >&2; exit 1; }

count_lines() { docker "$@" 2>/dev/null | grep -c . || true; }

stopped=$(count_lines ps -aq --filter status=exited --filter status=created)
dangling=$(count_lines images -q --filter dangling=true)
custom_net=$(count_lines network ls -q --filter type=custom)

echo "===== 当前占用 ====="
docker system df
echo
echo "已停止容器:   $stopped 个"
echo "悬空镜像:     $dangling 个"
echo "自定义网络:   $custom_net 个（未使用的会被清理）"

if [ "$apply" -eq 0 ]; then
    echo
    echo "dry-run：没有删除任何东西。确认上面数字合理后，加 --apply 执行。"
    exit 0
fi

echo
echo "开始清理..."
docker container prune -f
docker image prune -f
if [ "$all_images" -eq 1 ]; then
    echo "删除所有无容器引用的镜像 (--all-images)"
    docker image prune -a -f
fi
docker network prune -f
docker builder prune -f

echo
echo "===== 清理后 ====="
docker system df
