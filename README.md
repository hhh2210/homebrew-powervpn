# homebrew-powervpn

[powervpn-cli](https://github.com/hhh2210/powervpn-cli) 的 Homebrew tap —— LeadSec PowerVPN 的非官方 arm64 原生 macOS 命令行客户端。

## 安装

```sh
brew tap hhh2210/powervpn
brew install powervpn
```

> 当前 formula 从主仓库 `v0.1.0` 源码 tag 构建（无预编译 bottle），安装时在本机编译，需要几分钟。

## 前置要求

- macOS 14.4+，Apple silicon（本 formula 只构建 arm64）
- **完整 Xcode.app**（App Store 或 [developer.apple.com](https://developer.apple.com/download/)）。formula 声明 `depends_on xcode: :build`，**只装 Command Line Tools（`xcode-select --install`）不够，安装会失败**。装好后执行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`，并接受许可。
- 官方 PowerVPN.app 已安装，并至少成功用过一次（让 vendor helper 落位；本 CLI 复用它的隧道生命周期，不替代官方客户端安装）

## 首次配置

完整说明以主仓库 [README](https://github.com/hhh2210/powervpn-cli#readme) 为准：

- `~/.config/powervpn/credentials.env`（权限 0600）：`PORTAL_USERNAME` / `PORTAL_PASSWORD`
- 目标资源配置（如主 README 所述的 `~/.config/powervpn/targets.json`）

## 用法：SSH ProxyCommand（VS Code / Cursor Remote-SSH 同路径）

```sshconfig
Host campus-host
  HostName 192.0.2.10
  User <remote-user>
  Port 22
  ControlMaster no
  ProxyCommand /opt/homebrew/bin/powervpn proxy ssh --resource-display-name <resource> --ssh-target <ssh-target> %h %p --non-interactive
```

`%h` 必须展开为数字 IPv4（`HostName` 直接写数字地址，不接受主机名）；`--non-interactive` 必须是最后一个参数（Remote-SSH 没有 TTY）；`ControlMaster no` 防止后续连接绕过隧道。示例中的 `192.0.2.10` 与 `<…>` 均为占位符。
