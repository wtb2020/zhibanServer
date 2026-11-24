# 知伴课程服务端

本目录可独立复制或解压到服务器，负责用户、课程、数字物品和课程下载/更新授权。运行时使用 Python 3.10+ 标准库，不需要 pip 包。

Ubuntu LTS 通过 IP 部署并使用虚拟环境、systemd 常驻运行：请按 [Ubuntu 部署步骤](docs/UBUNTU.md) 操作。

## 启动

Windows 双击 **start.bat**，先检测/按需配置环境，服务就绪后自动打开 http://localhost:8000/admin。保持窗口打开。Linux / 远端服务器：

```sh
sh start.sh --no-browser -- --host 0.0.0.0 --port 8000
```

只配置环境用 setup.bat / `sh setup.sh`；只检查不安装用 `start.bat -CheckOnly` / `sh start.sh --check-only`。Windows 远端监听示例：

```powershell
.\start.bat -NoBrowser -BindAddress 0.0.0.0 -Port 8000
```

WinGet、apt-get、dnf 等自动安装的支持条件、网络和权限要求见 [环境配置](docs/ENVIRONMENT.md)。直接执行 `python run.py` 可用于已经配好环境的部署，它不会触发自动配置。

## 账号和密码

默认管理员 admin。首次创建时终端显示随机密码，请记录。已有数据库只显示用户名和重置提示，DEMO_ADMIN_PASSWORD 不会覆盖已存在密码。

忘记密码：Windows 双击 **reset_admin.bat**；Linux `sh reset_admin.sh`。输入两次 8–128 字符新密码，输入时不显示字符。自定义账号/数据库：

```powershell
.\reset_admin.bat -Username admin -Database D:\data\learning.db
```

```sh
sh reset_admin.sh -- --username admin --database /srv/zhiban/learning.db
```

重置保留用户、课程和授权，仅注销被重置管理员的旧会话。不要删除数据库或新建另一个数据库来重置密码。

## 管理功能

- 新建、编辑和删除多门课程，维护数字物品的图标、英文、中文和 RFID 绑定。
- 每门课程至少一个物品；物品 ID 和 RFID 在课程内唯一。
- 查看注册用户，启用/停用、删除学生，逐门授权课程下载/更新。管理员账号受保护。
- 新注册学生默认无课程；保存学生授权或状态会使其更新会话失效。
- 已下载课程继续在设备离线使用，服务端不远程删除离线副本，也不保存本地学习记录。

## 数据、部署与下载安装包

`data/learning.db` 是实际持久数据库；EDU_DATA_DIR 可指定其他数据目录。seed/course.json 只用于首次导入。数据库、密码与会话不进入分发 ZIP。迁移前根目录的数据库是历史备份，此目录数据才继续更新。

Docker 部署、HTTPS、备份、升级及数据卷迁移见 [部署文档](docs/DEPLOYMENT.md)。Compose 默认仅映射宿主 127.0.0.1:8000，公网由反向代理提供 HTTPS。容器已有 Python，不运行系统自动安装步骤。



