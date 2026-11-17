#!/bin/bash
set -euo pipefail

# 主机概览：系统、内核、运行时间、负载、CPU、内存、磁盘、Docker 版本。
# 只读，不改动任何东西。适合 SSH 上去先跑一把看看机器状态。

usage() {
    cat <<'USAGE'
用法: sysinfo.sh

只读地打印主机概览：发行版/内核、运行时间与负载、CPU、内存、磁盘占用、
Docker 版本与容器数、systemd 失败单元。磁盘占用 >=70% 的行会标 ▲。
不需要 root，但非 root 时部分信息（如 Docker 容器数）可能取不到。
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
esac

field() {
    if [ -n "$1" ]; then echo "$1"; else echo "-"; fi
}

echo "===== 主机 ====="
echo "主机名:   $(hostname 2>/dev/null || field "")"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "发行版:   $(field "${PRETTY_NAME:-}")"
fi
echo "内核:     $(uname -r 2>/dev/null || field "")"
echo "架构:     $(uname -m 2>/dev/null || field "")"

echo
echo "===== 运行时间 / 负载 ====="
if [ -r /proc/uptime ]; then
    secs=$(cut -d. -f1 /proc/uptime)
    echo "已运行:   $((secs / 86400)) 天 $((secs % 86400 / 3600)) 小时 $((secs % 3600 / 60)) 分钟"
fi
if [ -r /proc/loadavg ]; then
    read -r l1 l5 l15 _ < /proc/loadavg
    cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo || echo 1)
    echo "负载:     1min=$l1 5min=$l5 15min=$l15 CPU 核数=$cpus"
    awk -v l="$l1" -v c="$cpus" 'BEGIN{printf "        （1 分钟负载相当于 %.0f%% 的核数占用）\n", l/c*100}'
fi

echo
echo "===== CPU ====="
model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
echo "型号:     $(field "$model")"

echo
echo "===== 内存 ====="
if command -v free >/dev/null 2>&1; then
    free -h | awk 'NR==1 || /^Mem|^Swap/'
elif [ -r /proc/meminfo ]; then
    awk '/^MemTotal|^MemAvailable/{printf "%-14s %8.0f MB\n", $1, $2/1024}' /proc/meminfo
fi

echo
echo "===== 磁盘（已挂载的真实文件系统）====="
df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
    | awk 'NR==1 {print; next}
                  { pct=$5; sub(/%/,"",pct);
                    if (pct+0 >= 70) print "  ▲ " $0; else print "    " $0 }'

echo
echo "===== 服务 / Docker ====="
if command -v docker >/dev/null 2>&1; then
    echo "Docker:   $(docker --version 2>/dev/null || field '')"
    if docker info >/dev/null 2>&1; then
        echo "容器:     运行中 $(docker ps -q 2>/dev/null | grep -c . || echo 0) 个，总计 $(docker ps -aq 2>/dev/null | grep -c . || echo 0) 个"
    else
        echo "容器:     守护进程不可用（未启动或无权限）"
    fi
else
    echo "Docker:   未安装"
fi
if command -v systemctl >/dev/null 2>&1; then
    failed=$(systemctl --failed --no-legend --no-pager 2>/dev/null | grep -c . || true)
    echo "失败单元: ${failed:-0} 个"
    # 这里必须用 if：写成 `[ ... ] && cmd` 时，条件为假会让整个 AND 列表返回 1，
    # 而它是脚本最后一条命令，于是一台健康机器的退出码会变成 1。
    if [ "${failed:-0}" -gt 0 ]; then
        systemctl --failed --no-pager | head -n 10
    fi
fi
