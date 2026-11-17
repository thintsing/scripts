#!/bin/bash
set -euo pipefail

# 用途: 找出某路径下最占空间的目录/文件，回答「磁盘怎么满了」
# 依赖: du、sort、awk（GNU 或 busybox 均可）
# 权限: 普通用户即可；读不到的子目录会让结果偏小
# 退出: 0 成功 / 1 路径不存在 / 2 参数错误
# 示例: bash disk-top.sh /vol1 -d 2 -n 15

# 只读。用 du -k + 数值排序，不依赖 GNU 专属的 sort -h；du -d 在 GNU 和 busybox 上都能用。

usage() {
    cat <<'USAGE'
用法: disk-top.sh [路径] [-d 深度] [-n 条数] [-f] [-x]

  路径      要统计的目录，默认当前目录
  -d 深度   往下统计几层，默认 1
  -n 条数   显示前 N 行，默认 20
  -f        连文件一起统计（du -a，目录很大时会明显慢）
  -x        不跨越文件系统边界

示例:
  disk-top.sh /vol1 -d 2 -n 15
  disk-top.sh / -d 1 -x
USAGE
}

path="."
depth=1
top=20
du_args=("-k")
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -d|-n)
            [ $# -ge 2 ] || { echo "$1 需要一个参数" >&2; exit 2; }
            val="$2"
            case "$val" in ''|*[!0-9]*) echo "$1 需为正整数，收到: $val" >&2; exit 2 ;; esac
            if [ "$1" = "-d" ]; then depth="$val"; else top="$val"; fi
            shift 2 ;;
        -f) du_args+=("-a"); shift ;;
        -x) du_args+=("-x"); shift ;;
        -*) echo "未知选项: $1" >&2; usage >&2; exit 2 ;;
        *) path="$1"; shift ;;
    esac
done

[ -e "$path" ] || { echo "路径不存在: $path" >&2; exit 1; }
[ -r "$path" ] || echo "提示: 当前用户对 $path 没有读权限，结果会偏小（试试 sudo）" >&2

du_args+=("-d" "$depth" "$path")

out=$(du "${du_args[@]}" 2>/dev/null || true)
if [ -z "$out" ]; then
    echo "du 没有返回结果：可能是路径不可读，或本机 du 不支持 -d 选项" >&2
    exit 1
fi

echo "按占用从大到小（最多 $top 条）："
echo "------------------------------------------------------------"
# du 的输出是「大小<TAB>路径」，按 TAB 取字段才不会切断含空格的路径。
printf '%s\n' "$out" | sort -rn | head -n "$top" | awk -F'\t' '
    {
        kb = $1 + 0
        if (kb >= 1048576)   human = sprintf("%8.1f G", kb/1048576)
        else if (kb >= 1024) human = sprintf("%8.1f M", kb/1024)
        else                 human = sprintf("%8.0f K", kb)
        printf "%s  %s\n", human, $2
    }'
