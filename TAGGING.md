# 发版 / 打 tag 指引（维护者用）

Formula 从主仓库 [hhh2210/powervpn-cli](https://github.com/hhh2210/powervpn-cli) 的源码 tag 构建，没有 bottle。发布一个版本 = 在主仓库推 tag，再在本 tap 重算 sha256 并推送。

## 1. 在主仓库打 tag

前提：要发布的 commit 已在 `origin/main`，且该 commit 构建通过；tag 前跑一次 gitleaks 确认零命中（主仓库根已有 `.gitleaks.toml`）。

```sh
cd /path/to/powervpn-cli
swift build --product powervpn --arch arm64 -c release   # 确认可构建
git tag -a v0.1.0 -m "powervpn v0.1.0"
git push origin v0.1.0
```

## 2. 在本 tap 固化 sha256

```sh
cd /path/to/homebrew-powervpn
./scripts/release.sh 0.1.0
```

脚本依次执行：下载 `https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v0.1.0.tar.gz`（tag 未推送时 curl 直接 404 失败）→ 计算 sha256 → 空值 / `__SHA256__` / 非 64 位小写 hex 则拒绝写入 → 重写 `Formula/powervpn.rb` 的 `url` / `version` / `sha256` 三行 → `ruby -c` 语法检查 → 仅提交该 formula，并以 `git push origin HEAD:main` 推送（不依赖本地 upstream）。发下一个版本时同理，传新版本号即可（三行都会被重写）。

## 3. 验证安装

```sh
brew update
brew reinstall hhh2210/powervpn/powervpn --build-from-source
```

干净验证则先 `brew uninstall powervpn` 再 `brew install hhh2210/powervpn/powervpn --build-from-source`。