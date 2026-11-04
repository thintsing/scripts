#!/bin/bash
set -euo pipefail

# 用 rsync --link-dest 做「每次一个完整快照、未变文件共享数据块」的备份。
# 最常用的一条：把配置目录或数据目录按时间戳存起来，只保留最近 N 份。
# 默认 dry-run（只告诉你会同步哪些文件），加 --apply 才真的写。

usage() {
    cat <<'USAGE'
用法: rsync-snapshot.sh [选项] SRC DEST

  SRC          要备份的目录（会自动按「目录内容」处理，即末尾补 /）
  DEST         快照存放目录，内部每次新建一个时间戳子目录
  -k N         保留最近 N 份快照，默认 7（超出的最旧快照会被删除）
  --exclude P  排除模式，可重复传多次，例如 --exclude '*.tmp'
  --apply      真正执行同步与清理；不加就只是 dry-run

前提与坑：
  - DEST 下必须已经有至少一份快照，第二次开始才能用 --link-dest 省空间，
    第一份是全量复制，属正常现象。
  - DEST 必须与 SRC 在同一文件系统之外也无所谓，但同一台机器上 DEST 所在
    分区需要支持硬链接（本地 ext4/btrfs 可以，某些网络挂载不行）。
  - 删除旧快照只是断开硬链接，不会动到 SRC 的数据。
USAGE
}

keep=7
apply=0
src=""
dest=""
excludes=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -k)
            [ $# -ge 2 ] || { echo "-k 需要一个数字" >&2; exit 2; }
            case "$2" in ''|*[!0-9]*) echo "-k 需为正整数，收到: $2" >&2; exit 2 ;; esac
            keep="$2"; shift 2 ;;
        --exclude)
            [ $# -ge 2 ] || { echo "--exclude 需要一个模式" >&2; exit 2; }
            excludes+=("$2"); shift 2 ;;
        --apply) apply=1; shift ;;
        -*) echo "未知选项: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -z "$src" ]; then src="$1"
            elif [ -z "$dest" ]; then dest="$1"
            else echo "参数过多，多余的: $1" >&2; usage >&2; exit 2
            fi
            shift ;;
    esac
done

if [ -z "$src" ] || [ -z "$dest" ]; then
    echo "必须同时给出 SRC 和 DEST" >&2
    usage >&2
    exit 2
fi

command -v rsync >/dev/null 2>&1 || { echo "未找到 rsync 命令" >&2; exit 1; }
[ -d "$src" ] || { echo "SRC 不是一个目录: $src" >&2; exit 1; }

src="${src%/}/"
dest="${dest%/}"

if [ ! -d "$dest" ]; then
    if [ "$apply" -eq 1 ]; then
        mkdir -p "$dest" || { echo "无法创建 DEST: $dest" >&2; exit 1; }
    else
        echo "DEST 还不存在，dry-run 阶段先不创建: $dest"
    fi
fi

# 找最近一份快照作为 --link-dest 的参照
latest=""
if [ -d "$dest" ]; then
    latest=$(find "$dest" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)
fi

stamp=$(date +%Y-%m-%d_%H%M%S)
target="$dest/$stamp"

args=(-a -h -v --stats)
if [ "$apply" -eq 0 ]; then
    args+=(-n)
fi
# 数组可能为空，用 ${arr+...} 形式在 set -u 下安全展开
for p in ${excludes[@]+"${excludes[@]}"}; do
    args+=(--exclude "$p")
done
if [ -n "$latest" ]; then
    args+=(--link-dest "$(cd "$latest" && pwd)")
fi

echo "SRC      : $src"
echo "本次目标 : $target"
echo "参照快照 : ${latest:-（没有，这是第一份，全量复制）}"
echo "保留份数 : $keep"
echo "执行命令 : rsync ${args[*]} $src $target"
echo

rsync "${args[@]}" "$src" "$target" || {
    echo "rsync 执行失败" >&2
    exit 1
}

if [ "$apply" -eq 0 ]; then
    echo "dry-run：没有写入任何数据，也没有创建 $target。确认后加 --apply。"
    exit 0
fi

# 清理超出保留数量的旧快照
drop=0
mapfile -t snaps < <(find "$dest" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
total=${#snaps[@]}
if [ "$total" -gt "$keep" ]; then
    drop=$((total - keep))
    echo
    echo "删除最旧的 $drop 份快照："
    for ((i = 0; i < drop; i++)); do
        echo "  rm -rf ${snaps[$i]}"
        rm -rf -- "${snaps[$i]}"
    done
fi

echo
echo "保留的快照（共 $((total - drop)) 份）："
for s in "${snaps[@]:drop}"; do
    echo "  ${s#"$dest/"}"
done
