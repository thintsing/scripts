# FNOS Docker 延迟启动

为飞牛私有云（FNOS）设计的 Docker 容器延迟启动管理工具。通过交互式菜单，生成启动脚本并注册为 systemd 服务，实现 **开机后按指定顺序、间隔一定时间逐个启动 Docker 容器**，避免系统刚启动时因依赖未就绪导致的启动失败。

对应脚本：[`scripts/docker/docker-delay-for-fnos.sh`](../../scripts/docker/docker-delay-for-fnos.sh)

## 功能特性

- 交互式菜单：创建 / 删除延迟启动服务、查看启动日志、查看当前配置
- 自定义容器启动顺序与编号选择（支持单编号、区间 `1-5`、全选 `a`，自动去重）
- 可配置「系统启动后首个容器的等待时间」与「容器之间的启动间隔」
- 生成前展示配置摘要并二次确认，避免误操作
- 自动等待 Docker 守护进程就绪（最多约 2.5 分钟），超时则记录失败并退出
- 仅启动未运行的容器，已运行的会跳过
- 所有启动动作写入日志 `/var/log/start_docker.log`，便于排查

## 适用环境

- 系统：飞牛 FNOS（基于 Linux + systemd）
- 依赖：`docker`、`systemctl`、bash 4.0+
- 权限：需以 root 运行

## 快速开始（在线安装）

本脚本是交互式的（需要键盘输入），**必须先下载到本地再用 `sudo` 运行**，否则菜单无法读取输入。

方式一（推荐，两行）：

```bash
curl -fsSL -o /tmp/docker-delay-for-fnos.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-delay-for-fnos.sh
sudo bash /tmp/docker-delay-for-fnos.sh
```

方式二（一行，用 `bash -c` 传入脚本文本，stdin 仍指向终端，菜单可交互）：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-delay-for-fnos.sh)"
```

使用 wget 时，把下载那一步替换为：

```bash
wget -qO /tmp/docker-delay-for-fnos.sh https://raw.githubusercontent.com/thintsing/scripts/master/scripts/docker/docker-delay-for-fnos.sh
sudo bash /tmp/docker-delay-for-fnos.sh
```

> ⚠️ 不要用 `sudo bash <(curl ...)`：进程替换生成的 `/dev/fd/63` 文件描述符在 `sudo` 切换用户后无法被新进程继承，会报 `No such file or directory`。
> ⚠️ 也不要用 `curl ... | sudo bash`：脚本内的 `read` 会去读管道（curl 结束后即 EOF），菜单弹不出来。

## 使用方法

1. 如果走本地文件，先上传到 FNOS 并赋予执行权限：

   ```bash
   chmod +x docker-delay-for-fnos.sh
   sudo ./docker-delay-for-fnos.sh
   ```

2. 按菜单提示操作：
   - `1` 创建延迟启动服务：依次选择脚本保存目录、要启动的容器、等待秒数与间隔秒数，并在生成前**确认配置**，最后选择是否注册 systemd 服务。
     - 容器选择支持：单个编号 `1 3 5`、区间 `1-5`、全选 `a`（或 `*` / `all`）；重复选择会自动去重。
   - `2` 删除延迟启动服务：同时清理生成的启动脚本（孤儿文件不再残留）。
   - `3` 查看最近 100 行启动日志。
   - `4` 查看当前配置：列出已注册服务计划开机启动的容器顺序。
   - `5` 退出。

3. 启用后，服务会随系统开机自动运行。可用以下命令检查状态：

   ```bash
   systemctl status start_docker.service
   journalctl -u start_docker.service
   ```

## 工作原理

- 脚本根据用户选择，在指定目录生成 `start_docker.sh` 启动脚本（默认 `/vol1/1000/config/start_docker.sh`）。
- 该脚本会先 `sleep` 等待系统稳定，再轮询 `systemctl is-active docker`，待 Docker 就绪后按用户设定的顺序与间隔逐个 `docker start`。
- 同时注册 `start_docker.service`（`Type=oneshot`，`After=docker.service network-online.target`），并通过 `systemctl enable` 设为开机自启。

## 日志

启动过程的所有记录保存在：

```
/var/log/start_docker.log
```

可通过菜单 `3` 或 `tail -100 /var/log/start_docker.log` 查看。

## 注意事项

- 容器名称若包含空格，脚本已做引号处理，可正常启动。
- 删除服务时会一并删除生成的启动脚本；若仅想保留脚本而移除服务，请谨慎选择。
- 重复创建同名服务/脚本时会提示是否覆盖，避免误覆盖。
