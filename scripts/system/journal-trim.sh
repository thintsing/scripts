#!/bin/bash
set -euo pipefail

# 用途: 查看 systemd journal 占用，并按大小或时长收缩
# 依赖: journalctl（systemd）、du
# 权限: root
# 退出: 0 成功 / 1 非 root 或缺 journalctl / 2 参数错误
# 示例: sudo bash journal-trim.sh --size 200M --apply

# 默认 dry-run，只显示会执行什么；加 --apply 才收缩。

usage() {
    cat <<'USAGE'
用法: journal-trim.sh [--size 200M | --time 7d] [--apply]

  --size 200M  收缩到总量不超过该值（journalctl --vacuum-size）
  --time  7d   只保留最近该时长的日志（journalctl --vacuum-time）
  两者都不给时默认按 --size 200M 做计划
  --apply      真正执行收缩，否则只展示现状与将要执行的命令

长期方案应该改 /etc/systemd/journald.conf 的 SystemMaxUse=200M 然后
journalctl --flush，而不是反复手动 vacuum。
USAGE
}

size=""
keep_time=""

apply=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --size) [ $# -ge 2 ] || { echo "--size 需要一个参数，如 200M" >&2; exit 2; }
                size="$2"; shift 2 ;;
        --time) [ $# -ge 2 ] || { echo "--time 需要一个参数，如 7d" >&2; exit 2; }
                keep_time="$2"; shift 2 ;;
        --apply) apply=1; shift ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -n "$size" ] && [ -n "$keep_time" ]; then
    echo "--size 与 --time 互斥，只能给一个（同时给会静默丢掉其中一个）" >&2
    exit 2
fi

[ "$(id -u)" -eq 0 ] || { echo "需要 root 权限运行" >&2; exit 1; }
command -v journalctl >/dev/null 2>&1 || { echo "未找到 journalctl，这台机器可能不是 systemd 系统" >&2; exit 1; }

if [ -z "$size" ] && [ -z "$keep_time" ]; then
    size="200M"
fi

echo "===== journal 当前占用 ====="
journalctl --disk-usage 2>&1 || echo "（读取 journal 占用失败）"

echo
echo "===== /var/log 下最占地方的条目 ====="
if [ -d /var/log ]; then
    du -k -d 1 /var/log 2>/dev/null | sort -rn | head -n 10 | awk -F'\t' '
        { kb = $1 + 0
          if (kb >= 1048576)   h = sprintf("%7.1f G", kb/1048576)
          else if (kb >= 1024) h = sprintf("%7.1f M", kb/1024)
          else                 h = sprintf("%7.0f K", kb)
          printf "%s  %s\n", h, $2 }'
else
    echo "（没有 /var/log 目录）"
fi

echo
echo "===== 收缩计划 ====="
if [ -n "$size" ]; then
    plan="journalctl --vacuum-size=$size"
else
    plan="journalctl --vacuum-time=$keep_time"
fi
echo "$plan"

if [ "$apply" -eq 0 ]; then
    echo
    echo "dry-run：未做任何收缩。确认后加 --apply。"
    exit 0
fi

echo
$plan
echo
echo "收缩后："
journalctl --disk-usage 2>&1 || true
