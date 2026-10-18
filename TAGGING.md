# 发版 / 打 tag 指引（维护者用）

Formula 从主仓库 [hhh2210/powervpn-cli](https://github.com/hhh2210/powervpn-cli) 的源码 tag 构建；
macOS 15 及以上用 CI 编好的 bottle。发布一个版本 = 在主仓库推 tag → 在本 tap 开一个重算 sha256 的 PR →
CI 绿了以后用 publish 工作流发布 bottle。strongSwan resource 的 url/sha256 是单独 pin 的，release.sh 不会改它；
升级 strongSwan 时手动改，并同步主仓库的补丁序列。

下面以 0.2.0 为例，发其他版本时换掉版本号即可。

## 1. 在主仓库打 tag

前提：要发布的 commit 已在 `origin/main`，CI 通过，`powervpnVersion`（`Sources/PowerVPNCore/NativeBundledPayload.swift`）
已改成这个版本号（formula 的 test 会核对 `powervpn --version`）。

```sh
cd /path/to/powervpn-cli
git tag -a v0.2.0 -m "powervpn v0.2.0"
git push origin v0.2.0
```

## 2. 在本 tap 开 release PR

```sh
cd /path/to/homebrew-powervpn
./scripts/release.sh 0.2.0
```

脚本先确认工作区干净、`powervpn-0.2.0` 分支不存在，再下载
`https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v0.2.0.tar.gz`（tag 未推送时 curl 直接 404 失败）、
计算 sha256（不是 64 位小写 hex 就拒绝写入），从 `origin/main` 切出 `powervpn-0.2.0` 分支，
只改写 formula 顶层的 `url` / `sha256` 两行，`ruby -c` 检查后提交、推送，并用 `gh` 开 PR。

## 3. 发布 bottle

PR 上的 `brew test-bot` 在 macos-15 上编 bottle（`arm64_sequoia`，macOS 15 及更新的系统都会用它）。
检查全绿后：

```sh
gh workflow run publish.yml --repo hhh2210/homebrew-powervpn -f pull_request=<PR 号>
```

`brew pr-pull` 把 bottle 上传到本仓库的 `bottles` release，给 formula 加上 `bottle do` 块，连同 PR 的提交一起推到 main。

## 4. 验证

```sh
brew update
brew upgrade hhh2210/powervpn/powervpn      # 输出里应是 "Pouring powervpn--0.2.0.arm64_sequoia.bottle..."
powervpn --version
powervpn native status                      # 不是 up to date 就按 next: 重新安装 native 后端
```

只想验证源码编译（例如 macOS 14 的路径）时，另用 `brew reinstall --build-from-source hhh2210/powervpn/powervpn`。
