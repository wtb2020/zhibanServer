# 部署、启动与升级

以下命令均在对应独立项目目录执行。推荐先阅读 [环境自动配置](ENVIRONMENT.md)。

## 同机演示

完整仓库根目录双击 `启动演示.bat`；Linux 桌面可运行 `sh start.sh`。启动器先检查依赖，再运行服务端和客户端两个独立进程。有桌面且未指定跳过浏览器时会打开页面。

服务端默认 http://localhost:8000/admin，客户端默认 http://localhost:8765/client。保持服务窗口打开，Ctrl+C 停止。不要多次重复启动占用相同端口；Windows 服务端使用独占监听，冲突时给出错误。

## 服务端直接部署

Ubuntu LTS 推荐先在解压后的服务端目录创建虚拟环境：

```sh
sudo apt update
sudo apt install -y python3 python3-venv ca-certificates
python3 -m venv .venv
sh setup.sh
```

启动器会优先使用此 `.venv`，不需要 activate；目前不会自动创建虚拟环境。没有第三方 Python 包需要安装。长期运行可用 systemd，并将 ExecStart 指向项目 `.venv/bin/python` 的绝对路径，避免 SSH 退出后服务停止。

Windows：

```powershell
.\setup.bat
.\start.bat -NoBrowser -BindAddress 0.0.0.0 -Port 8000
```

Linux / 校园服务器：

```sh
sh setup.sh
sh start.sh --no-browser -- --host 0.0.0.0 --port 8000
```

只有在本机浏览器使用时，可直接双击 start.bat，默认监听 127.0.0.1 并自动打开页面。远端访问需要监听可达地址，并按实际网络设置防火墙；`localhost` 在客户设备上表示客户设备自身，不能用来指代远端服务器。

第一次创建数据库时，终端显示管理员 admin 的随机密码。之后仅显示账号和重置提示，不再显示密码。已有数据库不会因为设置 `DEMO_ADMIN_PASSWORD` 而更改密码。

## Docker 与反向代理

服务端包含 Dockerfile 和 deploy/compose.yaml，镜像中已有 Python，无需运行自动安装脚本。Docker/Compose 由运维预先安装，启动器不会安装它们。

```sh
docker compose -f deploy/compose.yaml up -d --build
docker compose -f deploy/compose.yaml logs courses
```

Compose 默认只映射宿主 127.0.0.1:8000，数据库位于具名卷 course-data。使用 HTTPS Nginx/云网关对外提供服务；`deploy/nginx.conf.example` 是 HTTP 反代和登录限流模板，需替换域名、增加有效 HTTPS 证书及 443 监听。不要将模板直接当作已经配置好 HTTPS 的部署。

将 `EDU_PUBLIC_URL` 设置为真实外部根地址，如 `https://learn.example.com`，再启动或重建容器。直接启动时用 `--public-url https://learn.example.com`。这用于 Origin 校验和 Secure Cookie；TLS 终止仍由反代负责。

镜像默认使用非 root 用户。数据卷必须允许进程写入。迁移现有账号需要将一致性数据库备份恢复到卷，Docker 不会自动导入仓库的 server/data/learning.db。不要执行删除具名数据卷的命令来“修复密码”。

## 客户端部署到电脑/机器人

将客户端 ZIP 解压到固定目录。Windows 双击 start.bat；Linux/树莓派运行 `sh setup.sh`、`sh start.sh`。有图形桌面时自动打开本机课堂；SSH 无桌面只运行本地程序，并提示需要设备上的浏览器。

客户端只监听 127.0.0.1，不提供面向局域网的设备记录管理入口。在设备的浏览器打开 http://localhost:8765/client，进入「课程下载与更新」，保存远端服务器根地址。不能填写 `/admin`、本地 8765 地址或带账号密码的 URL。

也可通过启动选项设置：

```powershell
.\start.bat -ServerUrl https://learn.example.com
```

```sh
sh start.sh -- --server https://learn.example.com
```

注册账号后让管理员分配课程，登录并下载。返回本地课堂测试 RFID 模拟、英语声音和拼写，然后断开远端服务器确认记录继续保存。不要只验证页面打开就认定硬件与音频正常。

## 升级和数据保留

1. 导出客户端完整设备备份；服务端用 SQLite backup API 或停机复制 learning.db 备份。
2. 停止对应进程，更新代码和启动器；保留服务端 data/、客户端 config.json，以及原浏览器网站数据。
3. 保持客户端浏览器、localhost 地址和端口不变，重新运行启动器。
4. 若需换设备/端口，在新设备通过「学习记录 → 导入设备备份」恢复。
5. 发布前运行打包脚本，客户端页面更新时递增 `client/static/sw.js` 的缓存版本。

本地原版从 8000 迁移至 8765：使用原浏览器和原网站地址打开服务端 `/migrate` 导出，再在新客户端导入。迁移页不会上传本地数据。

## 服务端密码重置

Windows 双击 reset_admin.bat；Linux 执行 `sh reset_admin.sh`；Docker 执行：

```sh
docker compose -f deploy/compose.yaml exec courses python reset_admin.py
```

输入两次 8–128 字符新密码，输入时不显示字符。默认账号 admin；Windows 可加 `-Username` / `-Database`，Linux 用 `--username` / `--database`。默认读取 EDU_DATA_DIR。不会删除用户、课程、授权或学生会话；管理员旧会话失效。

## 验收建议

服务端页面、登录、用户与课程管理正常；未授权账号无法下载；客户端可注册、配置地址并下载；断开远端后课堂仍启动；学习者切换不串记录；设备备份可恢复；真实 RFID 与本地英语声音经过试听。这些功能以外的公网安全审计、备份演练和机器人硬件适配仍需单独完成。
