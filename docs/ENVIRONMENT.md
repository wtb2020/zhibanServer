# 环境检测与自动配置

本文适用于完整仓库和独立服务端/客户端分发包。Windows 的 `.bat`、Linux 的 `.sh` 均先调用随包附带的 `bootstrap/`，无需预先安装 Python 才能执行检测脚本。

## 实际依赖

| 依赖 | 用途 | 启动器处理 |
| --- | --- | --- |
| Python 3.10+ | 运行服务端、本地客户端、密码重置工具 | 检测版本和实际可执行路径，不合格时尝试安装 |
| Python SQLite、SSL、PBKDF2、HTTP 等标准库 | 数据库、HTTPS、密码哈希、网络接口 | 实际导入和执行小型自检；不只检查 `python --version` |
| 系统 CA 证书 | 客户端验证远端 HTTPS 证书 | Linux 安装 Python 时一并安装 ca-certificates；不关闭证书校验 |
| Chrome / Edge / Chromium / Firefox | 打开教学界面 | 客户端或同机演示检测；缺少时按下述条件尝试安装浏览器 |
| 本地英语语音与音响 | 离线朗读 | 需要在操作系统中安装并在课堂试听；不保证自动安装 |
| RFID 读卡器 | 实体交互 | USB 键盘模式可直接输入；SPI/GPIO 驱动不自动安装 |

运行程序没有第三方 Python 包依赖，不需要 pip，也不会向系统 Python 安装 Python 包。浏览器是否能提供本地英语语音与具体系统有关；浏览器安装成功不等于离线语音已可用。

## 第一次启动会发生什么

1. 优先使用 `EDU_PYTHON` 指定的解释器；如果未指定，优先查找项目已有 `.venv`，再查找缓存路径、PATH、Windows py 启动器或常见安装目录。会保留虚拟环境解释器路径，不将 Linux 软链接解析回系统 Python。
2. 检查 Python 版本，导入 SQLite/SSL 等模块，执行 SQLite 内存查询与 PBKDF2 运算。
3. 没有合格解释器时，通过支持的系统包管理器安装，再重新检测；仍不满足就停止，保留错误提示。
4. 根据角色检查浏览器。远端服务器和密码重置不强制安装本地浏览器。
5. 在项目 `.runtime/` 保存 `python-path.txt` 与 `doctor.json`，然后启动程序。报告仅含解释器版本、路径和库版本，不记录密码和课堂记录。

已有合格依赖时不会重复安装，也不会自动升级它们。缓存路径失效会重新搜索。首次缺依赖的自动安装需要联网；依赖齐备后的客户端本地启动不需要联网。

## 虚拟环境

当前启动器会复用已有 `.venv`，但不会自动创建它。项目只有标准库依赖，不创建 venv 也能运行；Ubuntu 上长期部署建议先建立独立环境，便于后续维护：

```sh
sudo apt update
sudo apt install -y python3 python3-venv ca-certificates
python3 -m venv .venv
sh setup.sh
sh start.sh --no-browser -- --host 0.0.0.0 --port 8000  # 服务端
```

上述命令在服务端目录执行；客户端创建同名环境后运行自己的 start.sh 即可。启动器优先使用项目 `.venv`，不需要先执行 activate。也可用 `EDU_PYTHON="$PWD/.venv/bin/python"` 显式指定。Windows 已有 Python 时可执行 `python -m venv .venv`，随后双击启动脚本。

`.venv` 不随 ZIP 分发或跨机器复制，应在目标设备重建。自动安装的系统 Python 仍是虚拟环境的基础解释器，venv 不是独立安装一个 Python 版本。Docker 镜像直接使用容器内 Python，不必再嵌套创建 venv。

项目 `.venv` 存在但损坏时会停止并提示重建，不会静默改用系统 Python。启动器不会自动删除或覆盖已有虚拟环境。

## Windows

进入服务端或客户端目录，双击 `setup.bat`：只检测和补齐依赖，不启动服务。双击 `start.bat` 也会先执行相同检查，再打开界面。密码重置脚本同样检查 Python。

缺 Python 时通过 WinGet 安装 `Python.Python.3.14` 的当前用户版本；缺浏览器时尝试安装 `Google.Chrome` 的当前用户版本。安装通过包管理器校验，不下载执行来源不明的脚本，不忽略安装包哈希。命令使用静默安装和包/来源许可接受参数；运行前请确认你允许在该设备为当前用户安装相应软件。具体参数见 [Microsoft WinGet 文档](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)。Python 安装包标识参考 [Microsoft Python 安装说明](https://learn.microsoft.com/en-us/windows/python/scripting)。

Windows PowerShell 使用系统自带的 5.1 即可，不依赖 PowerShell 7。批处理仅为本次 PowerShell 进程设置执行策略，不修改系统执行策略。若系统策略强制禁用脚本或软件安装，仍需设备管理员协助。

```powershell
.\setup.bat                       # 检测并按需安装
.\start.bat -CheckOnly             # 只检查，不安装、不启动、不写 .runtime
.\start.bat -NoInstall             # 不允许安装；缺依赖直接停止
.\start.bat -NoBrowser             # 不检查/安装/自动打开浏览器，适合远端服务器
.\setup.bat -WithBrowser           # 显式补齐浏览器（客户端和演示默认会检查）
```

自定义 Python：在 PowerShell 中设置后再运行脚本。

```powershell
$env:EDU_PYTHON = 'C:\Python314\python.exe'
.\start.bat
```

`EDU_PYTHON` 必须是完整可执行文件路径，不能是带参数的命令字符串。指定后检测失败会直接停止，避免悄悄改用另一环境。

WinGet 不存在或安装失败时会给出明确失败原因。可先安装/修复 Microsoft App Installer，或从 [Python 官网](https://www.python.org/downloads/windows/) 安装 Python，再重试。不自动修改全机权限、不绕过 UAC、不保证企业管控设备能静默安装。

## Linux / 树莓派

```sh
sh setup.sh                       # 按需补齐 Python
sh setup.sh --with-browser        # 显式补齐浏览器
sh start.sh --check-only          # 只检查，不安装、不启动
sh start.sh --no-install          # 缺依赖直接失败
sh start.sh --no-browser          # 不安装/自动打开浏览器
EDU_PYTHON=/opt/python/bin/python3 sh start.sh
```

支持的自动安装路径：

| 包管理器 | Python 安装 | 浏览器安装 |
| --- | --- | --- |
| apt-get（Debian、Ubuntu、Raspberry Pi OS） | 更新索引，安装 python3、ca-certificates | 安装 chromium，失败后尝试 chromium-browser |
| dnf（使用 dnf 的 Linux） | 安装 python3、ca-certificates | 安装 chromium |
| 已安装的 Homebrew | 安装 python | 安装 google-chrome cask |

Linux 需要 root 或 sudo 权限，sudo 可能要求输入系统密码；脚本不会绕过这一要求。发行版软件源、网络、磁盘或包锁问题都会导致安装失败并停止。Homebrew 分支仅使用已有的 brew，不自动安装 Homebrew；macOS 桌面启动流程未做实机验证。

有 DISPLAY/WAYLAND_DISPLAY 的客户端或同机演示环境会检测并按需安装浏览器。无桌面的 SSH/服务器环境默认不装浏览器，并提示交互教学需要设备上的桌面浏览器。`--with-browser` 可显式请求安装，`--no-browser` 可跳过。

如果旧操作系统仓库只提供 Python 3.9 或更早版本，安装 python3 仍可能不合格。脚本会停止并提示升级操作系统或指定 `EDU_PYTHON`，不会替换系统 `/usr/bin/python3`、添加第三方软件源或自行编译 Python。

脚本选项应放在应用选项前，也可用 `--` 分隔：

```sh
sh start.sh --no-install -- --port 8080 --host 0.0.0.0  # 服务端
sh start.sh --no-browser -- --server https://learn.example.com  # 客户端
```

## 不由启动器自动安装的内容

Docker/Nginx、HTTPS 证书、系统桌面、声卡驱动、本地英语语音包、树莓派 RFID SPI 驱动以及开发测试用 Node.js 均不作为普通 Python 启动的自动安装项。相关配置见部署和硬件说明。直接执行 `python run.py` 或 `python client.py` 会绕过启动器的自动配置。

## 验证范围

Windows PowerShell 5.1 的真实 Python 检测已运行；缺 Python/浏览器的安装分支、失败退出和参数转发通过模拟包管理器测试。POSIX 脚本在 Git Bash 中完成语法、真实探测和模拟 apt 安装流程验证。未在这次开发中卸载或重装本机 Python，也未对全新树莓派、dnf 或 Homebrew 主机进行真实安装测试。
