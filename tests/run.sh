#!/bin/bash
# 仓库自测入口。用法: bash tests/run.sh
#
# 不依赖真实的 docker / systemd / rsync：全部用 tests/stubs/ 里的桩命令，
# 并把 PATH 收窄到一个只含必需工具的沙箱目录，这样「缺依赖」分支在
# Windows(Git Bash) 和 Linux(CI runner 自带 docker、netstat) 上行为一致。
#
# 退出码: 0 全通过 / 1 有断言失败
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
STUBS="$HERE/stubs"
BASH_BIN=$(command -v bash)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export STUB_LOG="$WORK/calls.log"
export FAKE_LOG_DIR="$WORK/logs"
mkdir -p "$FAKE_LOG_DIR" "$WORK/data" "$WORK/snaps"
: > "$STUB_LOG"

cd "$ROOT" || exit 1

# ---- 沙箱 PATH：只放脚本真正会用到的工具，故意不含 docker/ss/rsync/journalctl ----
BARE="$WORK/barebin"
MIN="$WORK/minbin"          # 同上，但额外提供 root 身份的 id 桩
mkdir -p "$BARE" "$MIN"
for t in awk cat cut date df du find grep head hostname id mkdir nproc paste printf rm sed sort stat tail tr uname wc; do
    p=$(command -v "$t" 2>/dev/null) || continue
    # printf 之类是 bash 内建命令，command -v 只回名字不回路径，跳过
    case "$p" in /*) ;; *) continue ;; esac
    # 用 exec 包装而不是 cp：Git Bash 的 *.exe 依赖同目录的 msys-2.0.dll，
    # 拷出 /usr/bin 就加载不到 DLL，命令就静默变成「输出为空」。
    printf '#!/bin/bash\nexec "%s" "$@"\n' "$p" > "$BARE/$t"
done
cp "$BARE"/* "$MIN/" 2>/dev/null || true
cp "$STUBS/id" "$MIN/id"
chmod +x "$BARE"/* "$MIN"/* "$STUBS"/* 2>/dev/null

pass=0; fail=0; skip=0
chk() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1)); printf '  ok    %s\n' "$1"
    else
        fail=$((fail + 1)); printf '  FAIL  %s | 期望[%s] 实际[%s]\n' "$1" "$2" "$3"
    fi
}
skipped() { skip=$((skip + 1)); printf '  skip  %s\n' "$1"; }
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }
run()      { out=$("$BASH_BIN" "$@" 2>&1); code=$?; }
run_stub() { out=$(PATH="$STUBS:$PATH" "$BASH_BIN" "$@" 2>&1); code=$?; }
run_bare() { out=$(PATH="$BARE" "$BASH_BIN" "$@" 2>&1); code=$?; }
run_min()  { out=$(PATH="$MIN" "$BASH_BIN" "$@" 2>&1); code=$?; }
# 场景开关必须传给子进程，不能写成 `VAR=1 run_stub ...`：bash 对函数的
# 赋值前缀会残留到后续调用，把后面的测试全污染掉。
# 这里用子 shell 里的 export 而不是 env(1)：有些机器 ~/.local/bin/env 是
# 一个只改 PATH 的安装器脚本，会把它后面的命令整个吞掉。
run_env()  { local e="$1"; shift; out=$(export "$e"; PATH="$STUBS:$PATH" "$BASH_BIN" "$@" 2>&1); code=$?; }
reset_log() { : > "$STUB_LOG"; }
calls() { grep -c -e "$1" "$STUB_LOG" 2>/dev/null || true; }

mapfile -t SCRIPTS < <(find scripts -name '*.sh' | sort)

echo "=========== 仓库级检查 ==========="
for f in "${SCRIPTS[@]}"; do
    base=$(basename "$f")
    chk "$base 有 bash shebang" "#!/bin/bash" "$(head -n 1 "$f")"
    chk "$base 纯 LF 行尾"      0 "$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')"
    if bash -n "$f" 2>/dev/null; then
        pass=$((pass + 1)); printf '  ok    %s bash -n\n' "$base"
    else
        fail=$((fail + 1)); printf '  FAIL  %s bash -n\n' "$base"
    fi
    run "$f" --help
    chk "$base --help 退出 0"   0 "$code"
    chk "$base --help 有用法"   yes "$(has '用法' "$out")"
    chk "$base 出现在 README 索引" yes "$(has "$base" "$(cat README.md)")"
    mode=$(git ls-files -s -- "$f" 2>/dev/null | awk '{print $1}')
    if [ -n "$mode" ]; then
        chk "$base git 模式 100755" 100755 "$mode"
    else
        skipped "$base 执行位（未被 git 跟踪）"
    fi
    # 交互式菜单脚本不吃参数，跳过未知参数检查
    if [ "$base" != "docker-delay-for-fnos.sh" ]; then
        run "$f" --definitely-not-a-flag
        chk "$base 未知参数退出 2" 2 "$code"
    fi
done

echo
echo "=========== docker-cleanup ==========="
reset_log
run_stub scripts/docker/docker-cleanup.sh
chk "默认退出 0"            0 "$code"
chk "默认提示 dry-run"      yes "$(has 'dry-run' "$out")"
chk "默认不调用任何 prune"  0 "$(calls 'prune')"
chk "未使用网络数为 1 而非 2" yes "$(has '未使用网络:   1 个' "$out")"
reset_log
run_stub scripts/docker/docker-cleanup.sh --apply
chk "--apply 调 container prune" 1 "$(calls 'container prune')"
chk "--apply 调 builder prune"   1 "$(calls 'builder prune')"
reset_log
run_stub scripts/docker/docker-cleanup.sh --apply --all-images
chk "--all-images 调 image prune -a" 1 "$(calls 'image prune -a')"
reset_log
run_env STUB_BUILDER_FAIL=1 scripts/docker/docker-cleanup.sh --apply
chk "builder 失败仍打印清理后汇总" yes "$(has '===== 清理后 =====' "$out")"
chk "builder 失败标记为 skip"      yes "$(has '[skip] 构建缓存' "$out")"
chk "builder 失败前面的步骤已执行"  1 "$(calls 'container prune')"
chk "builder 失败诚实返回 1"        1 "$code"

echo
echo "=========== docker-inventory ==========="
run_stub scripts/docker/docker-inventory.sh
chk "退出 0"                0 "$code"
chk "表头含 restart"        yes "$(has 'restart' "$out")"
chk "restart 列未错位"      yes "$(has 'unless-stopped' "$out")"
chk "列出两个容器"          2 "$(printf '%s\n' "$out" | grep -c '^c[12] ')"
run_stub scripts/docker/docker-inventory.sh -o "$WORK/inv.tsv"
chk "TSV 6 字段=5 个 TAB"   5 "$(head -n 1 "$WORK/inv.tsv" | tr -cd '\t' | wc -c | tr -d ' ')"
chk "TSV 行数=表头+2容器"   3 "$(wc -l < "$WORK/inv.tsv" | tr -d ' ')"

echo
echo "=========== docker-log-trim ==========="
printf 'x%.0s' $(seq 1 200) > "$FAKE_LOG_DIR/c1.json"
printf 'y%.0s' $(seq 1 300) > "$FAKE_LOG_DIR/c2.json"
reset_log
run_stub scripts/docker/docker-log-trim.sh --over 0
chk "退出 0"                 0 "$code"
chk "列出超阈值日志"         yes "$(has 'c1.json' "$out")"
chk "dry-run 不调 truncate"  0 "$(calls 'truncate')"
chk "dry-run 文件未被清空"   200 "$(stat -c %s "$FAKE_LOG_DIR/c1.json")"
reset_log
run_stub scripts/docker/docker-log-trim.sh --over 0 --apply
chk "--apply 调 truncate"    1 "$(calls 'truncate')"
chk "--apply 文件真的清零"   0 "$(stat -c %s "$FAKE_LOG_DIR/c1.json")"
reset_log
run_stub scripts/docker/docker-log-trim.sh --over 0 --all
chk "--all 走 docker ps -aq" 1 "$(calls 'ps -aq')"
run_stub scripts/docker/docker-log-trim.sh --over abc
chk "非数字阈值退出 2"       2 "$code"
run_env STUB_UID=1000 scripts/docker/docker-log-trim.sh
chk "非 root 拒绝执行"       1 "$code"
chk "非 root 报错文本"       yes "$(has '需要 root' "$out")"
run_min scripts/docker/docker-log-trim.sh
chk "缺 docker 退出 1"       1 "$code"
chk "缺 docker 报错文本"     yes "$(has '未找到 docker 命令' "$out")"

echo
echo "=========== journal-trim ==========="
reset_log
run_stub scripts/system/journal-trim.sh
chk "默认计划 vacuum-size=200M" yes "$(has '--vacuum-size=200M' "$out")"
chk "dry-run 不调 vacuum"       0 "$(calls 'vacuum')"
reset_log
run_stub scripts/system/journal-trim.sh --time 7d --apply
chk "--apply 调 vacuum-time=7d" 1 "$(calls '--vacuum-time=7d')"
run_stub scripts/system/journal-trim.sh --size 500M --time 3d
chk "--size/--time 互斥退出 2"  2 "$code"
chk "互斥报错文本"              yes "$(has '互斥' "$out")"
run_min scripts/system/journal-trim.sh
chk "缺 journalctl 退出 1"      1 "$code"

echo
echo "=========== ports ==========="
run_stub scripts/network/ports.sh
chk "退出 0"              0 "$code"
chk "列出 4 条监听"       4 "$(printf '%s\n' "$out" | grep -c 'LISTEN\|UNCONN')"
chk "统计行正确"          yes "$(has '共 4 条' "$out")"
run_stub scripts/network/ports.sh 8080
chk "过滤 8080 命中 1 条" 1 "$(printf '%s\n' "$out" | grep -c ':8080')"
run_stub scripts/network/ports.sh 99999
chk "无命中有提示"        yes "$(has '没有匹配' "$out")"
run_bare scripts/network/ports.sh
chk "缺 ss/netstat 退出 1" 1 "$code"
chk "缺 ss 报错文本"       yes "$(has '需要 ss' "$out")"

echo
echo "=========== disk-top ==========="
mkdir -p "$WORK/data/a" "$WORK/data/b" "$WORK/data/c"
printf 'B%.0s' $(seq 1 9000) > "$WORK/data/b/data.bin"
printf 'C%.0s' $(seq 1 100)  > "$WORK/data/c/small.bin"
run_stub scripts/system/disk-top.sh "$WORK/data" -d 1 -n 3
chk "退出 0"        0 "$code"
rank_b=$(printf '%s\n' "$out" | grep -n '/b$' | cut -d: -f1)
rank_c=$(printf '%s\n' "$out" | grep -n '/c$' | cut -d: -f1)
chk "大目录排在小目录前" yes "$([ -n "$rank_b" ] && [ -n "$rank_c" ] && [ "$rank_b" -lt "$rank_c" ] && echo yes || echo no)"
run_stub scripts/system/disk-top.sh "$WORK/data/missing"
chk "路径不存在退出 1" 1 "$code"
run_stub scripts/system/disk-top.sh -d abc
chk "-d 非整数退出 2"  2 "$code"
run_stub scripts/system/disk-top.sh -n
chk "-n 缺参数退出 2"  2 "$code"

echo
echo "=========== rsync-snapshot ==========="
reset_log
run_stub scripts/backup/rsync-snapshot.sh "$WORK/data" "$WORK/snaps"
chk "dry-run 退出 0"        0 "$code"
chk "dry-run 传了 -n"       1 "$(calls 'rsync -a -h -v --stats -n')"
chk "dry-run 未建快照目录"  0 "$(find "$WORK/snaps" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
reset_log
run_stub scripts/backup/rsync-snapshot.sh --apply "$WORK/data" "$WORK/snaps"
chk "--apply 建出一份快照"  1 "$(find "$WORK/snaps" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
chk "--apply 未传 -n"       0 "$(calls ' -n ')"
sleep 1
reset_log
run_stub scripts/backup/rsync-snapshot.sh --apply "$WORK/data" "$WORK/snaps"
chk "第二次用上 --link-dest" 1 "$(calls '--link-dest')"
chk "共两份快照"             2 "$(find "$WORK/snaps" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
for _ in 1 2 3; do
    sleep 1
    run_stub scripts/backup/rsync-snapshot.sh --apply -k 2 "$WORK/data" "$WORK/snaps"
done
chk "-k 2 稳定保留两份"      2 "$(find "$WORK/snaps" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
run_stub scripts/backup/rsync-snapshot.sh "$WORK/data"
chk "缺 DEST 退出 2"         2 "$code"
run_bare scripts/backup/rsync-snapshot.sh "$WORK/data" "$WORK/snaps"
chk "缺 rsync 退出 1"        1 "$code"
chk "缺 rsync 报错文本"      yes "$(has '未找到 rsync 命令' "$out")"

echo
echo "=========== sysinfo（P0 回归守卫）==========="
# 关键场景：有 systemctl 且没有失败单元。开发机常没装 systemctl，
# 缺了这个桩就测不出「健康机器退出码 1」那个 bug。
reset_log
run_stub scripts/system/sysinfo.sh
chk "有 systemctl+无失败单元 退出 0" 0 "$code"
chk "打印失败单元 0 个"              yes "$(has '失败单元: 0 个' "$out")"
chk "打印了 Docker 版本"             yes "$(has 'Docker version' "$out")"
run_env STUB_FAILED_UNITS=1 scripts/system/sysinfo.sh
chk "有失败单元时仍退出 0"           0 "$code"
chk "有失败单元时列出单元名"         yes "$(has 'nginx.service' "$out")"
run_bare scripts/system/sysinfo.sh
chk "无 docker/systemctl 也退出 0"   0 "$code"
chk "无 docker 时如实说未安装"       yes "$(has 'Docker:   未安装' "$out")"

echo
echo "=========== docker-delay-for-fnos ==========="
run scripts/docker/docker-delay-for-fnos.sh --help
chk "--help 退出 0（不需要 root）" 0 "$code"
chk "--help 提到菜单"              yes "$(has '创建延迟启动服务' "$out")"
# 这个脚本的 root 判断用的是 bash 内建 $EUID，桩命令改不了它。
# 好在 CI runner 和 Windows 开发机本来就不是 root，直接用真实身份测。
if [ "$EUID" -ne 0 ]; then
    run scripts/docker/docker-delay-for-fnos.sh </dev/null
    chk "非 root 拒绝进入菜单"   1 "$code"
    chk "非 root 报错文本"       yes "$(has '请使用root权限运行' "$out")"
else
    skipped "非 root 拒绝进入菜单（当前是 root，无法就地验证）"
fi

echo
printf '=========== 通过 %d，失败 %d，跳过 %d ===========\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
