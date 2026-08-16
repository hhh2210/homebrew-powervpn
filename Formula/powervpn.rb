class Powervpn < Formula
  desc "Unofficial arm64-native macOS CLI for the LeadSec PowerVPN client"
  homepage "https://github.com/hhh2210/powervpn-cli"
  url "https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  # Placeholder until the v0.1.0 tag exists upstream; scripts/release.sh downloads
  # the tarball, computes the digest and rewrites this line. All-zero digest is
  # intentional: brew fetch/install will fail until a real tag is pinned.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  # Source build: swift(1) ships with Apple's developer tools, so there is no
  # "swift" Homebrew dependency; :xcode gates the build toolchain instead.
  # This requires full Xcode.app — Command Line Tools alone is not enough.
  depends_on xcode: :build
  # Upstream product line is arm64-only (built with --arch arm64).
  depends_on arch: :arm64
  # Package.swift declares platforms: [.macOS(.v14)].
  depends_on macos: :sonoma

  def install
    # Same invocation as upstream scripts/build_and_run.sh.
    system "swift", "build", "--product", "powervpn", "--arch", "arm64", "-c", "release"
    # Resolve the built binary the same way upstream does, via --show-bin-path:
    # layout-independent (Xcode 16+ xcbuild layout puts it under
    # .build/out/Products/Release; classic SwiftPM layout uses
    # .build/arm64-apple-macosx/release).
    bin_path = Utils.safe_popen_read(
      "swift", "build", "--product", "powervpn", "--arch", "arm64", "-c", "release", "--show-bin-path"
    ).strip
    bin.install "#{bin_path}/powervpn"
  end

  test do
    assert_predicate bin/"powervpn", :executable?
    # "--help" only prints usage (Sources/PowerVPNCLI/main.swift routes
    # help/--help/-h to printCLIUsage()) and touches no local PowerVPN state,
    # unlike subcommands such as status/doctor which inspect the live system.
    assert_match "Usage: powervpn", shell_output("#{bin}/powervpn --help")
  end
end
