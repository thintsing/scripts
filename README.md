# scripts

[![CI](https://github.com/thintsing/scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/thintsing/scripts/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](scripts)

我个人在用的运维脚本仓库。目标环境是飞牛 FNOS（Debian + systemd）和普通 Linux 服务器。

两条贯穿全仓库的规矩：

- **自包含单文件** —— `curl` 下来就能跑，不用 clone、不用装依赖、不 `source` 仓库里的其他文件。
- **默认 dry-run** —— 凡是会删除、覆盖、写系统文件的脚本，不加 `--apply` 就只报告不动手。这条是给未来的自己保命的。

## 脚本索引

### docker/

| 脚本 | 作用 | 改动系统 | 权限 |
| --- | --- | --- | --- |
| [docker-delay-for-fnos.sh](scripts/docker/docker-delay-for-fnos.sh) | 开机后按顺序、隔指定秒数逐个启动容器，规避依赖未就绪；交互式注册 systemd 服务（[详细文档](docs/docker/docker-delay-for-fnos.md)） | 是，写 systemd 单元 | root |
| [docker-cleanup.sh](scripts/docker/docker-cleanup.sh) | 清理已停止容器、悬空镜像、未使用网络、构建缓存 | 需 `--apply` | docker 组 |
| [docker-inventory.sh](scripts/docker/docker-inventory.sh) | 导出容器清单（镜像/状态/重启策略/挂载/端口），重装系统前留档 | 否，只读 | docker 组 |
| [docker-log-trim.sh](scripts/docker/docker-log-trim.sh) | 找出并清空撑爆磁盘的容器 json 日志 | 需 `--apply` | root |

```bash
# 延迟启动（交互式菜单，必须先下载到文件再跑）
curl -fsSL -o /tmp/docker-delay-for-fnos.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-delay-for-fnos.sh && sudo bash /tmp/docker-delay-for-fnos.sh

# 清理：先 dry-run 看清数量，确认后把结尾改成 --apply
curl -fsSL -o /tmp/docker-cleanup.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-cleanup.sh && bash /tmp/docker-cleanup.sh

# 容器清单留档（刻意不导出容器 env，避免把密码写进存档）
curl -fsSL -o /tmp/docker-inventory.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-inventory.sh && bash /tmp/docker-inventory.sh -o ~/containers.tsv

# 日志体检：--all 连已停止容器一起算，确认后加 --apply
curl -fsSL -o /tmp/docker-log-trim.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-log-trim.sh && sudo bash /tmp/docker-log-trim.sh --over 100 --all
```

### system/

| 脚本 | 作用 | 改动系统 | 权限 |
| --- | --- | --- | --- |
| [sysinfo.sh](scripts/system/sysinfo.sh) | 主机概览：内核、负载、内存、磁盘、Docker、失败单元 | 否，只读 | 普通用户 |
| [disk-top.sh](scripts/system/disk-top.sh) | 某路径下最占空间的东西，回答「磁盘怎么满了」 | 否，只读 | 普通用户 |
| [journal-trim.sh](scripts/system/journal-trim.sh) | 查看 journal 占用并按大小/时长收缩 | 需 `--apply` | root |

```bash
# SSH 上去先跑这一把
curl -fsSL -o /tmp/sysinfo.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/system/sysinfo.sh && bash /tmp/sysinfo.sh

# 磁盘满了：从根往下挖一层，不跨文件系统
curl -fsSL -o /tmp/disk-top.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/system/disk-top.sh && bash /tmp/disk-top.sh / -d 1 -x

# journal 收缩：先看计划，确认后加 --apply
curl -fsSL -o /tmp/journal-trim.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/system/journal-trim.sh && sudo bash /tmp/journal-trim.sh --size 200M
```

### network/

| 脚本 | 作用 | 改动系统 | 权限 |
| --- | --- | --- | --- |
| [ports.sh](scripts/network/ports.sh) | 列出监听端口及持有它的进程，可按端口号过滤 | 否，只读 | 普通用户（root 才看得全进程名） |

```bash
# 末尾加端口号可过滤，例如 ... && bash /tmp/ports.sh 8080
curl -fsSL -o /tmp/ports.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/network/ports.sh && bash /tmp/ports.sh
```

### backup/

| 脚本 | 作用 | 改动系统 | 权限 |
| --- | --- | --- | --- |
| [rsync-snapshot.sh](scripts/backup/rsync-snapshot.sh) | `--link-dest` 时间戳快照，未变文件共享数据块，保留最近 N 份 | 需 `--apply` | 对 SRC 可读、DEST 可写 |

```bash
# 换成自己的目录；先看会同步什么，确认后加 --apply
curl -fsSL -o /tmp/rsync-snapshot.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/backup/rsync-snapshot.sh && bash /tmp/rsync-snapshot.sh ~/config ~/backup/config
```

## 运行方式

上面的命令都是同一个套路：**下载到 `/tmp` → 先跑一次看输出 → 确认后加 `--apply`**。

```bash
curl -fsSL -o /tmp/<脚本名>.sh \
  https://raw.githubusercontent.com/thintsing/scripts/master/scripts/<分类>/<脚本名>.sh
bash /tmp/<脚本名>.sh            # 会改东西的脚本此时是 dry-run
sudo bash /tmp/<脚本名>.sh --apply
```

每条脚本都支持 `-h` / `--help`，里面有完整参数说明和坑位提示。

> **交互式脚本必须先下载到文件再运行。**
> `curl ... | sudo bash` 不行——脚本里的 `read` 会去读管道，curl 一结束就是 EOF，菜单弹不出来。
> `sudo bash <(curl ...)` 也不行——进程替换产生的 `/dev/fd/63` 在 `sudo` 切换用户后不被新进程继承，会报 `No such file or directory`。

## 退出码约定

| 码 | 含义 | 典型场景 |
| --- | --- | --- |
| `0` | 成功 | 含 dry-run 正常结束、过滤无命中 |
| `1` | 运行期问题 | 缺依赖、非 root、路径不存在、Docker 守护进程不可用、有清理步骤未完成 |
| `2` | 参数错误 | 未知选项、选项缺参数、`--size` 与 `--time` 互斥、阈值不是整数 |

写 cron 或串在别的脚本里时，按这个约定判断即可：`2` 是调用方写错了，`1` 是机器状态不对。

## 目录结构

```
scripts/
  docker/     Docker 容器与镜像的日常维护
  system/     主机状态、磁盘占用、journal 日志
  network/    端口与连通性
  backup/     快照式备份
docs/         需要长说明的脚本，按同样的分类目录放同名 .md
tests/
  run.sh      桩测试入口：bash tests/run.sh
  stubs/      docker / systemctl / journalctl / rsync / ss / id / truncate 的桩命令
.github/      CI：bash -n + 桩测试 + shellcheck
```

## 自测与 CI

```bash
bash tests/run.sh
```

不需要真的 Docker、systemd 或 rsync：全部走 `tests/stubs/` 里的桩命令，并把 `PATH` 收窄到一个只含必需工具的沙箱，这样「缺依赖」分支在 Windows(Git Bash) 和 Linux(CI runner 自带 docker、netstat) 上行为一致。

覆盖的场景包括：正常路径、参数错误、缺依赖、非 root、**dry-run 不产生任何副作用**、以及几个已经踩过的回归坑（健康机器上 `sysinfo` 退出码变 1、老版本 Docker 缺 `builder prune` 时清理半路掐断、`--size`/`--time` 同时给被静默丢掉一个）。

仓库级检查也在里面：shebang、纯 LF 行尾、`bash -n`、git 执行位 `100755`、`--help` 可用、以及**每条脚本都必须出现在本 README 的索引里**。

CI（`.github/workflows/ci.yml`）在 push 和 PR 时跑同样的检查，外加 shellcheck。

## 仓库约定

- **分类目录**：`scripts/<分类>/<名字>.sh`，kebab-case。分类够用就行，不要为了两三个脚本开新目录。
- **统一脚本头**：`用途 / 依赖 / 权限 / 退出 / 示例` 五行，打开文件第一眼就知道能不能跑、要不要 sudo。
- **行尾**：全部 LF，由 `.gitattributes` 强制，`.editorconfig` 兜住编辑器。Windows 上 `core.autocrlf=true` 会把工作区转成 CRLF，不锁死的话哪天在无 autocrlf 的环境提交一次，`#!/bin/bash\r` 就能让脚本在 Linux 上直接跑不起来。
- **自包含**：不 `source` 仓库内的其他文件，不用相对路径依赖，这样 `curl` 单文件才真的能用。
- **root 自检**：需要 root 的脚本自己检查并报错退出，不假设调用者已经 `sudo`。
- **导出信息别带密钥**：`docker-inventory.sh` 刻意不导容器 env，里面通常是数据库密码和 API key。
- **少依赖 GNU 专属特性**：`du -d` 而不是 `--max-depth`，`sort -rn` 而不是 `sort -h`，busybox 环境也能跑。

## 添加一条新脚本

1. 建 `scripts/<分类>/<名字>.sh`，抄一份现有脚本的五行头部，`chmod +x`。
2. 会改东西的，默认分支必须零副作用，真正的动作放在 `--apply` 后面。
3. 补 `-h|--help` 与未知参数退出 `2`；参数解析放在 root 检查之前，这样不 sudo 也能看帮助。
4. 在 `tests/run.sh` 里加断言，跑 `bash tests/run.sh` 到全绿。
5. 长说明放 `docs/<分类>/<名字>.md`，并在上面对应的索引表加一行（CI 会检查索引覆盖率）。

## 许可

[MIT](LICENSE)。脚本按原样提供，生产环境请先在测试机上验证——尤其是带 `--apply` 的那几条。