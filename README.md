# scripts

我个人在用的运维脚本仓库。目标环境是飞牛 FNOS（Debian + systemd）和普通 Linux 服务器。

每条脚本都是自包含单文件，`curl` 下来就能跑，不需要 clone、没有依赖安装步骤。

## 目录结构

```
scripts/
  docker/     Docker 容器与镜像的日常维护
  system/     主机状态、磁盘占用、journal 日志
  network/    端口与连通性
  backup/     快照式备份
docs/         需要长说明的脚本，按同样的分类目录放同名 .md
```

## 脚本索引

### docker/

| 脚本 | 作用 | 是否改动系统 |
| --- | --- | --- |
| [docker-delay-for-fnos.sh](scripts/docker/docker-delay-for-fnos.sh) | 开机后按顺序、隔指定秒数逐个启动容器，规避依赖未就绪；交互式注册 systemd 服务。[详细文档](docs/docker/docker-delay-for-fnos.md) | 是（写 systemd 单元） |
| [docker-cleanup.sh](scripts/docker/docker-cleanup.sh) | 清理已停止容器、悬空镜像、未使用网络、构建缓存 | 默认否，需 `--apply` |
| [docker-inventory.sh](scripts/docker/docker-inventory.sh) | 导出容器清单（镜像/状态/重启策略/挂载/端口），重装系统前留档 | 否，只读 |
| [docker-log-trim.sh](scripts/docker/docker-log-trim.sh) | 找出并清空撑爆磁盘的容器 json 日志 | 默认否，需 `--apply` |

### system/

| 脚本 | 作用 | 是否改动系统 |
| --- | --- | --- |
| [sysinfo.sh](scripts/system/sysinfo.sh) | 主机概览：内核、负载、内存、磁盘、Docker、失败单元 | 否，只读 |
| [disk-top.sh](scripts/system/disk-top.sh) | 某路径下最占空间的东西，回答「磁盘怎么满了」 | 否，只读 |
| [journal-trim.sh](scripts/system/journal-trim.sh) | 查看 journal 占用并按大小/时长收缩 | 默认否，需 `--apply` |

### network/

| 脚本 | 作用 | 是否改动系统 |
| --- | --- | --- |
| [ports.sh](scripts/network/ports.sh) | 列出监听端口及持有它的进程，可按端口号过滤 | 否，只读 |

### backup/

| 脚本 | 作用 | 是否改动系统 |
| --- | --- | --- |
| [rsync-snapshot.sh](scripts/backup/rsync-snapshot.sh) | `--link-dest` 时间戳快照，保留最近 N 份 | 默认否，需 `--apply` |

## 通用运行方式

```bash
# 1) 下载
curl -fsSL -o /tmp/<脚本名>.sh \
  https://raw.githubusercontent.com/thintsing/scripts/master/scripts/<分类>/<脚本名>.sh
# 2) 先看它想干什么（所有会改动的脚本默认 dry-run）
bash /tmp/<脚本名>.sh
# 3) 确认输出合理后，再真正执行
sudo bash /tmp/<脚本名>.sh --apply
```

**交互式脚本（要读键盘输入的，比如 docker-delay）必须先下载到文件再运行**，否则脚本里的 `read` 会去读管道，curl 一结束就是 EOF，菜单弹不出来。同理 `sudo bash <(curl ...)` 也不行——进程替换产生的 `/dev/fd/63` 在 `sudo` 切换用户后不会被新进程继承，会报 `No such file or directory`。

## 仓库约定

- **分类目录**：`scripts/<分类>/<名字>.sh`，kebab-case。分类够用就行，不要为了两三个脚本开新目录。
- **dry-run 优先**：任何会删除、覆盖、写系统文件的脚本，默认只报告不执行，真正的动作必须显式加 `--apply`。这条是给未来的自己保命的。
- **行尾**：全部 LF，由 `.gitattributes` 强制。Windows 上 `core.autocrlf=true` 会把工作区转成 CRLF，不锁死的话哪天在无 autocrlf 的环境提交一次，`#!/bin/bash\r` 就能让脚本在 Linux 上直接跑不起来。
- **自包含**：不 `source` 仓库内的其他文件，不用相对路径依赖，这样 `curl` 单文件才真的能用。
- **需要 root 的脚本自己检查** `id -u` 并报错退出，不假设调用者已经 `sudo`。
- **导出信息别带密钥**：像 `docker-inventory.sh` 刻意不导容器 env，里面通常是数据库密码。

## 添加一条新脚本

1. `scripts/<分类>/<名字>.sh`，头部注释写清用途、依赖、是否需要 root。
2. `bash -n` 语法检查；涉及删除/写文件的，确认默认分支不产生任何副作用。
3. 长说明放 `docs/<分类>/<名字>.md`，并在上面对应的索引表加一行。
4. 提交。

## 许可

脚本仅供学习与自用，使用风险自负。生产环境请先在测试机上验证。
