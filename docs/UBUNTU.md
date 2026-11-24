# Ubuntu LTS：使用服务器 IP 部署演示

本指南使用独立 `.venv`、专用系统用户和 systemd，服务在 SSH 断开后继续运行，并可开机自动启动。服务端安装包来自本仓库 dist/zhiban-server.zip；客户端仍运行在客户电脑或机器人本地。

本机自检启动器目前会优先复用已有 `.venv`，不会自动创建它。以下命令负责创建虚拟环境。项目没有第三方 Python 包，无需 pip install。

## 1. 上传与系统依赖

将 zhiban-server.zip 上传到服务器登录用户的家目录。可用 SFTP、服务器面板，或本机 PowerShell：

```powershell
scp "C:\Users\47628\Documents\ChatGPT\智能学习系统\dist\zhiban-server.zip" 用户名@服务器IP:~/
```

将用户名和服务器IP换成实际值。以下命令在 SSH 登录后的 Ubuntu 服务器执行，需要 sudo 权限：

```sh
sudo apt update
sudo apt install -y python3 python3-venv ca-certificates unzip
python3 --version
```

Python 必须至少 3.10。若旧版 Ubuntu 仓库只能提供更早版本，不要替换系统 Python；使用较新的系统或由管理员准备独立解释器。venv 创建方式可参考 [Ubuntu 官方说明](https://documentation.ubuntu.com/ubuntu-for-developers/tutorials/python-use/)。

## 2. 解压并创建独立运行用户

以下按首次部署到新目录编写。已有部署应先备份数据库，不要覆盖 data/。

```sh
sudo mkdir -p /opt/zhiban
sudo unzip "$HOME/zhiban-server.zip" -d /opt/zhiban
id zhiban
```

若最后一步提示该用户不存在，执行一次：

```sh
sudo useradd --system --user-group --home-dir /opt/zhiban/zhiban-server --shell /usr/sbin/nologin zhiban
```

然后设置目录归属并创建虚拟环境：

```sh
sudo chown -R zhiban:zhiban /opt/zhiban/zhiban-server
sudo -u zhiban python3 -m venv /opt/zhiban/zhiban-server/.venv
sudo -u zhiban /opt/zhiban/zhiban-server/.venv/bin/python /opt/zhiban/zhiban-server/bootstrap/runtime_doctor.py
```

自检应显示解释器位于 `.venv/bin/python` 且 `Virtual environment: True`。无需 activate；运行服务时明确指定这个 Python。虚拟环境不应从 Windows 复制，也不随 ZIP 分发。Python 官方同样支持通过完整解释器路径直接运行 [venv 文档](https://docs.python.org/3.12/library/venv.html)。

## 3. 安装为常驻服务

包内已提供与上述目录匹配的 systemd 模板：

```sh
sudo cp /opt/zhiban/zhiban-server/deploy/zhiban.service.example /etc/systemd/system/zhiban.service
sudo systemctl daemon-reload
sudo systemctl enable --now zhiban
sudo systemctl status zhiban --no-pager
sudo journalctl -u zhiban -n 80 --no-pager
```

首次创建数据库时，日志显示用户名 admin 和随机密码，请记录。此后不重复显示密码。服务以专用 zhiban 用户运行，不以 root 运行；进程退出时重启，开机自动启动。不需另开 start.sh，否则会占用同一端口。

## 4. 放行演示访问并打开页面

在云厂商安全组中允许 TCP 8000，演示时建议仅允许你和测试客户端的公网来源 IP。如果 Ubuntu 已启用 UFW，也允许相应来源访问 8000；不要为了此服务直接启用或重置 UFW，避免影响现有 SSH 访问。

浏览器访问：

```text
http://服务器公网IP:8000/admin
```

首页为 http://服务器公网IP:8000/，提供客户端 ZIP 下载。此处必须是服务器可达的 IP，不是客户电脑上的 localhost。

该 IP 演示使用普通 HTTP，登录凭据不受 TLS 传输保护，适合受限来源的临时演示。长期公网使用应配置域名和 HTTPS 反代；届时将服务监听改为 127.0.0.1，并设置真实 --public-url，见 DEPLOYMENT.md。

## 5. 客户端连接

客户电脑/机器人本地启动客户端，在“课程下载与更新”中保存：

```text
http://服务器公网IP:8000
```

不要附加 /admin。注册账号后，管理员在服务器管理页面给该账号授权课程，客户端登录下载。下载后，本地课堂可在服务器关闭时继续教学和保存记录。

## 管理命令

```sh
sudo systemctl restart zhiban
sudo systemctl stop zhiban
sudo journalctl -u zhiban -f
```

密码重置使用同一解释器、用户和数据库：

```sh
sudo -u zhiban /opt/zhiban/zhiban-server/.venv/bin/python /opt/zhiban/zhiban-server/reset_admin.py
```

如果 status 显示失败，先看 journalctl 中的首个错误。若本机可访问而外部不可访问，检查安全组、UFW 和公网 IP；不要反复重复启动。数据库位于 /opt/zhiban/zhiban-server/data/learning.db，升级前做一致性备份，不要删除它来处理登录问题。
