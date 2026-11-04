# scripts

我个人在用的运维脚本仓库。目前主要面向飞牛 FNOS（Debian + systemd）和普通 Linux 服务器。

每条脚本都是自包含的单文件，直接 `curl` 下来就能跑，不需要 clone、没有依赖安装步骤。

## 脚本索引

| 脚本 | 作用 | 运行方式 | 文档 |
| --- | --- | --- | --- |
| [docker-delay-for-fnos.sh](scripts/docker-delay-for-fnos.sh) | 让 FNOS 的 Docker 容器在开机后按顺序、隔指定秒数逐个启动，避免依赖未就绪导致启动失败；交互式生成启动脚本并注册 systemd 服务 | `sudo bash`，需 root | [文档](docs/docker-delay-for-fnos.md) |

## 通用运行方式

非交互脚本可以直接管道执行：

```bash
curl -fsSL https://raw.githubusercontent.com/thintsing/scripts/master/scripts/<脚本名>.sh | bash
```

**交互式脚本（需要读键盘输入的，比如上面那个）必须先下载到文件再运行**，否则脚本里的 `read` 会去读管道，curl 一结束就是 EOF，菜单根本弹不出来：

```bash
curl -fsSL -o /tmp/<脚本名>.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/<脚本名>.sh
sudo bash /tmp/<脚本名>.sh
```

同理，`sudo bash <(curl ...)` 也不行——进程替换产生的 `/dev/fd/63` 文件描述符在 `sudo` 切换用户后不会被新进程继承，会报 `No such file or directory`。

## 仓库约定

- **目录**：脚本一律放在 `scripts/`，一层平铺，文件名用 kebab-case + `.sh`。详细说明放 `docs/<脚本名>.md`，并在上面的索引表里加一行。
- **行尾**：全部 LF，由 `.gitattributes` 强制。Windows 上 `core.autocrlf=true` 会把工作区文件转成 CRLF，如果不锁死，哪天在无 autocrlf 的环境里提交一次，`#!/bin/bash\r` 就能让脚本在 Linux 上直接跑不起来。
- **权限**：需要 root 的脚本自己检查 `EUID` 并报错退出，不假设调用者已经 `sudo`。
- **自包含**：不引入仓库内的相对路径依赖，跨目录的 `source` 一律不用，这样 `curl` 单文件才真的能用。

## 添加一条新脚本

1. `scripts/<名字>.sh` 写脚本，头部注释说明用途、适用环境、是否需要 root。
2. `docs/<名字>.md` 写用法，包含上面那种可直接复制的 `curl` 命令。
3. 更新本文件的索引表。
4. 提交前跑一次 `bash -n scripts/<名字>.sh` 做语法检查。

## 许可

脚本仅供学习与自用，使用风险自负。生产环境请先在测试机上验证。
