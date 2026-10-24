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

## 一条命令跑完第 2–4 步

tag 推送后，在本 tap 的 checkout 里运行：

```sh
./scripts/ship.sh 0.2.0
```

`ship.sh` 按顺序完成下面第 2–4 步，失败即停：

1. 等主仓库 `tap-sync.yml` 对这个 tag 的 CI 跑完，CI 必须全绿。
2. 调用 `release.sh` 开 release PR。如果已有打开的同名 PR，就直接用那个。
3. 等 PR 上的 bottle 构建跑完。
4. 带上 PR 当前的 head sha 触发 `publish.yml`，并等它跑完，确认 main 上的 formula 已经带上 bottle。
5. 运行 `brew update` 和 `brew upgrade`，核对 `powervpn --version`，以及安装的确实是 bottle。
6. 最后运行 `powervpn native status`。

所有对 GitHub 的操作都用本机的 `gh` 登录完成，CI 里不存任何能写本 tap 的凭据。
中途断了可以直接重跑：已经发布的版本会跳过前面的步骤，直接做本机升级。
它唯一不做的是 root 安装：native 后端需要重装时，脚本把 `sudo … native install` 打印在 `next:` 行，由你本人执行。

下面是第 2–4 步的手动做法，脚本出错时照着排查。

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
