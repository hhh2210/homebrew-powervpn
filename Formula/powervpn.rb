class Powervpn < Formula
  desc "Reach servers behind THU LeadSec PowerVPN with a patched strongSwan"
  homepage "https://github.com/hhh2210/powervpn-cli"
  url "https://github.com/hhh2210/powervpn-cli/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "63581fedd44f90aeedac5fe8b87e251826ecc9d895c8742130cb16284dc3836f"
  # powervpn-cli is MIT. The bundled charon runtime is strongSwan
  # (GPL-2.0-or-later) with a private copy of OpenSSL's libcrypto (Apache-2.0).
  license all_of: ["MIT", "GPL-2.0-or-later", "Apache-2.0"]

  bottle do
    root_url "https://github.com/hhh2210/homebrew-powervpn/releases/download/bottles"
    sha256 arm64_sequoia: "614e9a27c81f5ab2975c835590f8ba58b3c2a42efc4486ab5d8e107b0719aa44"
  end

  # Source build. swift(1) from the Command Line Tools is enough; full Xcode is
  # not needed. These are needed only to build the patched strongSwan runtime,
  # which links a private libcrypto copy, so none are runtime dependencies.
  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "bison" => :build
  depends_on "gettext" => :build
  depends_on "gperf" => :build
  depends_on "libtool" => :build
  depends_on "openssl@3" => :build
  depends_on "pkgconf" => :build
  depends_on arch: :arm64
  depends_on macos: :sonoma

  # Patched by scripts/native/build_runtime.sh with patches/strongswan-6.0.7.
  resource "strongswan" do
    url "https://github.com/strongswan/strongswan/archive/refs/tags/6.0.7.tar.gz"
    sha256 "1e49a277979a5248bf1979472dd56612a6b159519c8ae55561302be337ed5632"
  end

  def install
    swift_args = [*std_swift_args, "--arch", "arm64"]
    %w[powervpn powervpn-native-helper].each do |product|
      system "swift", "build", *swift_args, "--product", product
    end
    bin_path = Utils.safe_popen_read("swift", "build", *swift_args, "--show-bin-path").strip
    bin.install "#{bin_path}/powervpn"

    resource("strongswan").stage buildpath/"strongswan"
    ENV["BREW_PREFIX"] = HOMEBREW_PREFIX
    system "scripts/native/build_runtime.sh", "--source", buildpath/"strongswan", buildpath/"native"

    # `sudo powervpn native install` copies these into the root-owned helper
    # directory; the daemon never runs from this user-writable keg. The
    # runtime stays a tar so Homebrew never relocates its Mach-O files.
    (libexec/"powervpn-native").install "#{bin_path}/powervpn-native-helper",
                                        "scripts/native/install.sh",
                                        "scripts/native/uninstall.sh",
                                        buildpath/"native/runtime.tar"
    pkgshare.install "docs/targets.example.json"
  end

  def caveats
    <<~EOS
      The native backend needs one root install, and another after an upgrade
      that changes it (`powervpn native status` tells you):
        sudo #{opt_bin}/powervpn native install

      Credentials, targets and SSH setup:
        #{homepage}#readme
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/powervpn --version").strip

    payload = libexec/"powervpn-native"
    targets = '{"targets": {"lab": {"host": "192.0.2.21", "user": "u", "resource": "r"}}}'
    assert_equal "192.0.2.21",
                 pipe_output("#{payload}/powervpn-native-helper host-policy", targets).strip
    assert_match "./libexec/ipsec/charon", shell_output("tar -tf #{payload}/runtime.tar")

    # Installing needs root; without it the CLI refuses and names the command.
    output = shell_output("#{bin}/powervpn native install 2>&1", 77)
    assert_match "native install", output
  end
end
