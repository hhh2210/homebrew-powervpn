# homebrew-powervpn

[powervpn-cli](https://github.com/hhh2210/powervpn-cli) 的 Homebrew tap。用命令行连清华 LeadSec PowerVPN 后面的服务器，
隧道由打过补丁的 strongSwan 建立，原生 arm64，**不需要安装官方 PowerVPN 客户端**。

## 前置要求

- Apple silicon，macOS 14 或更新
- Homebrew。它会顺带装好 Xcode Command Line Tools，不需要完整 Xcode。

## 安装

**1. 装 powervpn**

```sh
brew install hhh2210/powervpn/powervpn
```

macOS 15 及更新的系统直接下载预编译 bottle，几秒装好。macOS 14 没有 bottle，
会在本机从源码编译 CLI、root helper 和 strongSwan 6.0.7，约几分钟。

**2. 写账号密码和要连的服务器**

`~/.config/powervpn/credentials.env` 和 `~/.config/powervpn/targets.json`（需写 `"backend": "native"`），
按主仓库 [README](https://github.com/hhh2210/powervpn-cli#readme) 的「第一次使用」第 2、3 步写。
示例在 `$(brew --prefix)/share/powervpn/targets.example.json`。

**3. 安装 native 后端（一次 sudo）**

```sh
sudo "$(brew --prefix)/bin/powervpn" native install
```

它读取第 2 步的 `targets.json`，把目标 IP 固定进 root 拥有的路由白名单，所以要在写好配置之后执行；
以后改了目标 IP 也要重新执行一次。helper 和 strongSwan 运行时被复制进
`/Library/PrivilegedHelperTools/com.hhh2210.powervpn-native/`，校验后由一个 LaunchDaemon 运行。
装好之后常驻的 root 进程从不执行 Homebrew 目录（当前用户可写）里的文件；
安装这一步本身和任何 sudo 命令一样，信任你自己账户下的文件。

**4. 配 SSH 并连一次**

按主仓库 README 的第 5、6 步配 `~/.ssh/config`，然后 `powervpn doctor`、`powervpn ssh <目标> -- hostname`。

## 升级与卸载

```sh
brew upgrade powervpn
powervpn native status
```

`native status` 显示 up to date 就不用再 sudo；否则照它最后一行 `next:` 给出的命令重新安装 native 后端
（`powervpn doctor` 也会提示）。重新安装会断开正在用的会话，下一次 `powervpn run` 会自动重连。

```sh
sudo "$(brew --prefix)/bin/powervpn" native uninstall
brew uninstall powervpn
```

## 许可

powervpn-cli 是 MIT。编译出的运行时包含 strongSwan（GPL-2.0-or-later）和 OpenSSL libcrypto 的私有副本（Apache-2.0），
许可证文本随运行时安装在 `runtime/share/licenses/`。

bottle 的 cellar 固定为 `/opt/homebrew/Cellar`（运行时里的 libcrypto 带有 Homebrew 默认路径），
这正是 Apple silicon 上 Homebrew 的默认位置；装在其他前缀时会自动改为从源码编译。
