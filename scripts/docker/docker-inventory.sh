#!/bin/bash
set -euo pipefail

# 导出所有 Docker 容器的清单（名称/镜像/状态/重启策略/挂载/端口映射），TSV 格式。
# 重装系统或挪机器之前先跑一遍，手里就有一份「这台机器上到底跑了些什么」的记录。
# 刻意不导出容器环境变量：里面通常是数据库密码和 API key，不该落到一个存档文件里。

usage() {
    cat <<'USAGE'
用法: docker-inventory.sh [-o 文件.tsv]

  无参数   以对齐表格打印到终端（本机没有 column 命令时退回纯 TSV）
  -o FILE  同时把原始 TSV 写入 FILE，方便丢进表格软件
USAGE
}

out_file=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -o) [ $# -ge 2 ] || { echo "-o 需要一个文件名" >&2; exit 2; }
            out_file="$2"; shift 2 ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v docker >/dev/null 2>&1 || { echo "未找到 docker 命令" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker 守护进程不可用，或当前用户无权访问 docker.sock" >&2; exit 1; }

mapfile -t ids < <(docker ps -aq)
if [ ${#ids[@]} -eq 0 ]; then
    echo "没有任何容器"
    exit 0
fi

# 每个字段各跑一次 inspect，再用 paste 横向拼成 TSV，
# 这样 Go 模板里不用嵌制表符，也就不会被编辑器把 tab 转成空格搞坏。
rows() {
    paste \
        <(docker inspect --format '{{.Name}}' "${ids[@]}" | sed 's|^/||') \
        <(docker inspect --format '{{.Config.Image}}' "${ids[@]}") \
        <(docker inspect --format '{{.State.Status}}' "${ids[@]}") \
        <(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${ids[@]}") \
        <(docker inspect --format '{{range .Mounts}}{{.Source}}=>{{.Destination}}; {{end}}' "${ids[@]}") \
        <(docker inspect --format '{{range $p, $c := .NetworkSettings.Ports}}{{if $c}}{{$p}}=>{{(index $c 0).HostPort}}; {{end}}{{end}}' "${ids[@]}")
}

header=$'name\timage\tstatus\trestart\tmounts\tports'

if [ -n "$out_file" ]; then
    { echo "$header"; rows; } > "$out_file"
    echo "已写入 $out_file（共 ${#ids[@]} 个容器）"
fi

if command -v column >/dev/null 2>&1; then
    { echo "$header"; rows; } | column -t -s $'\t'
else
    { echo "$header"; rows; }
fi
