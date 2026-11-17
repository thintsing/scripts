#!/bin/bash
set -euo pipefail

# 用途: 找出并清空撑爆磁盘的容器 json-file 日志
# 依赖: docker、stat、truncate、awk（coreutils）
# 权限: root
# 退出: 0 成功 / 1 非 root 或 docker 不可用 / 2 参数错误
# 示例: sudo bash docker-log-trim.sh --over 100 --all --apply

# json-file 驱动默认不限制日志大小，长期运行的容器能把系统盘撑爆。
# 默认 dry-run 只列出超过阈值的日志；--apply 用 truncate -s 0 清零。

usage() {
    cat <<'USAGE'
用法: docker-log-trim.sh [--over MB] [--all] [--apply]

  --over MB   只处理大于该体积的日志，默认 100
  --all       连已停止的容器一起算（它们的日志同样躺在盘上占空间）
  --apply     真正执行 truncate -s 0，否则只列出

更省心的做法是让 Docker 自己轮转，而不是靠手动清：在 compose 里给服务加
    logging: { driver: json-file, options: { max-size: "50m", max-file: "3" } }
或者写进 /etc/docker/daemon.json 的 log-opts，之后这个脚本就只用于救急。
USAGE
}

over_mb=100
apply=0
all=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --over) [ $# -ge 2 ] || { echo "--over 需要一个数字" >&2; exit 2; }
                over_mb="$2"; shift 2 ;;
        --all) all=1; shift ;;
        --apply) apply=1; shift ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$over_mb" in
    ''|*[!0-9]*) echo "--over 需为非负整数（单位 MB）" >&2; exit 2 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "需要 root 权限运行" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "未找到 docker 命令" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker 守护进程不可用，或当前用户无权访问 docker.sock" >&2; exit 1; }

threshold=$((over_mb * 1024 * 1024))
total_over=0
hits=0

if [ "$all" -eq 1 ]; then
    ps_args=(-aq)
    scope="全部容器"
else
    ps_args=(-q)
    scope="运行中的容器"
fi

while IFS= read -r id; do
    [ -n "$id" ] || continue
    name=$(docker inspect --format '{{.Name}}' "$id" | sed 's|^/||')
    logpath=$(docker inspect --format '{{.LogPath}}' "$id")
    [ -f "$logpath" ] || continue

    size=$(stat -c %s "$logpath")
    if [ "$size" -ge "$threshold" ]; then
        hits=$((hits + 1))
        total_over=$((total_over + size))
        printf '%8.1f MB  %s  %s\n' "$(echo "$size" | awk '{printf "%.1f", $1/1048576}')" "$name" "$logpath"
        if [ "$apply" -eq 1 ]; then
            truncate -s 0 "$logpath"
            echo "    -> 已清空 $logpath"
        fi
    fi
done < <(docker ps "${ps_args[@]}")

mb_total=$(awk -v n="$total_over" 'BEGIN{printf "%.1f", n/1048576}')
echo
echo "$scope 里，超过 ${over_mb} MB 的日志: ${hits} 个，合计 ${mb_total} MB"
if [ "$apply" -eq 0 ]; then
    echo "dry-run：未清空任何文件。确认后加 --apply。"
else
    echo "已全部清空。注意：正在写入的容器日志文件会变成稀疏文件，"
    echo " apparent size 会再次增长，用 du 看实际占用更准。"
fi
