#!/bin/bash
set -euo pipefail

# 用途: 清理已停止容器、悬空镜像、未使用自定义网络、构建缓存
# 依赖: docker CLI，且当前用户能访问 docker.sock
# 权限: root 或 docker 组
# 退出: 0 成功 / 1 docker 不可用或有清理步骤未完成 / 2 参数错误
# 示例: bash docker-cleanup.sh --apply

# 默认 dry-run 只报告，加 --apply 才真正删除。
# --apply 会删掉 exited 状态的容器：靠 stop 保留数据、以后还要 start 的别直接加。

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

# 只数「没有任何容器连着」的自定义网络。数全部自定义网络会虚高，
# 因为 compose 建的网络大多正在被使用，prune 根本不会碰它们。
unused_net=0
while IFS= read -r net; do
    [ -n "$net" ] || continue
    attached=$(docker network inspect --format '{{len .Containers}}' "$net" 2>/dev/null || echo 0)
    case "$attached" in ''|*[!0-9]*) attached=0 ;; esac
    if [ "$attached" -eq 0 ]; then
        unused_net=$((unused_net + 1))
    fi
done < <(docker network ls -q --filter type=custom 2>/dev/null || true)

echo "===== 当前占用 ====="
docker system df
echo
echo "已停止容器:   $stopped 个"
echo "悬空镜像:     $dangling 个"
echo "未使用网络:   $unused_net 个"

if [ "$apply" -eq 0 ]; then
    echo
    echo "dry-run：没有删除任何东西。确认上面数字合理后，加 --apply 执行。"
    exit 0
fi

# 每一步单独兜住失败：老版本 Docker 没有 builder prune 之类的子命令，
# 不能让 set -e 把脚本掐断在半路——前面已经删了东西，却连汇总都不打印。
failures=0
step() {
    local desc="$1" out
    shift
    if out=$("$@" 2>&1); then
        printf '  [ok]   %s\n' "$desc"
    else
        printf '  [skip] %s —— %s\n' "$desc" "$(printf '%s' "$out" | tail -n 1)"
        failures=$((failures + 1))
    fi
}

echo
echo "开始清理..."
step "已停止容器"   docker container prune -f
step "悬空镜像"     docker image prune -f
if [ "$all_images" -eq 1 ]; then
    step "无引用镜像" docker image prune -a -f
fi
step "未使用网络"   docker network prune -f
step "构建缓存"     docker builder prune -f

echo
echo "===== 清理后 ====="
docker system df

if [ "$failures" -gt 0 ]; then
    echo
    echo "有 $failures 步未完成（常见原因是该 Docker 版本不支持对应子命令），其余步骤已执行。"
    exit 1
fi
