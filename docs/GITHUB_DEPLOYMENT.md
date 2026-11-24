# 独立服务端 GitHub 更新

本仓库根目录就是服务端：run.py、backend.py、static/，没有额外的 server/ 层。

首次上传：在 GitHub 建立空仓库，然后在本目录执行：
```
git add .
git diff --cached --stat
git commit -m "Initial course server"
git branch -M main
git remote add origin https://github.com/OWNER/REPO.git
git push -u origin main
```
先检查暂存文件，真实数据库、虚拟环境、密码和令牌不要提交。

服务器首次迁移：克隆到新目录（例如 /root/zhiban-server），停止 zhiban 服务后备份旧 data，复制旧数据库到新目录 data。若 EDU_DATA_DIR 指向外置数据目录，继续保留该环境变量。旧项目保留以便回退。在新仓库根目录运行 python3 -m venv .venv，再 sh setup.sh。

systemd 路径改为：
```
WorkingDirectory=/root/zhiban-server
ExecStart=/root/zhiban-server/.venv/bin/python -u /root/zhiban-server/run.py --host 0.0.0.0 --port 8001
```
执行 systemctl daemon-reload，再 systemctl start zhiban。检查状态、旧账号课程，以及 http://127.0.0.1:8001/api/status。

日常更新：本地测试后提交推送；服务器在仓库根目录先 git fetch origin、git status，确认无本地代码改动。停止服务，备份实际数据库目录，记录 git rev-parse HEAD 的旧提交，然后 git pull --ff-only，sh setup.sh，systemctl start zhiban，检查状态及接口。任何步骤失败先排查，不继续执行。只有修改 unit 文件才需 daemon-reload。

Git 仅管理程序，后台编辑的课程与用户存于 SQLite，不通过 Git 发布。客户端已下载内容仍可离线使用。
