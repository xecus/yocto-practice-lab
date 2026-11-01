#!/bin/bash

# 環境を作る。何度実行してもよい（できているところは飛ばす）。
#   1. ホストの確認（パッケージ、ロケール、ユーザー名前空間）
#   2. bitbake-setup を venv に入れる
#   3. bitbake-setup init で Poky（Wrynose）を取得し、DISTRO poky・MACHINE qemuarm64 にする
#   4. meta-practice・meta-practice-bsp を追加し、practice/lowmem と root ログインのフラグメントを有効にする
# 詳しくは docs/01-build-and-runqemu.md

set -e
cd "$(dirname "$0")"
TOP=$(pwd)

BITBAKE_SETUP_VERSION=2.19.0
SETUP_CONFIG=poky-wrynose

# ---- 1. ホストの確認 ----
# System Requirements の Ubuntu / Debian 向けの一覧と python3-websockets・lz4
PKGS="build-essential chrpath cpio debianutils diffstat file gawk gcc git iputils-ping libacl1
      libcrypt-dev locales python3 python3-git python3-jinja2 python3-pexpect python3-pip
      python3-subunit socat texinfo unzip wget xz-utils zstd python3-websockets lz4"
MISSING=
for p in $PKGS; do
    dpkg -s "$p" > /dev/null 2>&1 || MISSING="$MISSING $p"
done
# venv は Ubuntu では python3.12-venv などの別パッケージ。パッケージ名ではなく、使えるかで確かめる
python3 -c 'import ensurepip' 2> /dev/null || MISSING="$MISSING python3-venv"
if [ -n "$MISSING" ]; then
    echo "足りないパッケージがあります。次を実行してください:" >&2
    echo "  sudo apt-get install$MISSING" >&2
    exit 1
fi

locale -a | grep -qi '^en_US.utf8$' || {
    echo "en_US.UTF-8 ロケールがありません。sudo dpkg-reconfigure locales で追加してください" >&2
    exit 1
}

# BitBake はタスク中のネットワークを止めるためにユーザー名前空間を使う。
# Ubuntu 24.04 は AppArmor で制限しているので、外しておく必要がある。
if ! unshare --user --map-root-user true 2> /dev/null; then
    echo "ユーザー名前空間が使えません（Ubuntu 24.04 の AppArmor の制限）。次を実行してください:" >&2
    echo "  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/60-bitbake-userns.conf" >&2
    echo "  sudo sysctl --system" >&2
    exit 1
fi

# ---- 2. bitbake-setup ----
if [ ! -x bitbake-setup-venv/bin/bitbake-setup ]; then
    python3 -m venv --clear ./bitbake-setup-venv
    ./bitbake-setup-venv/bin/pip install -q "bitbake-setup==$BITBAKE_SETUP_VERSION"
fi
. ./bitbake-setup-venv/bin/activate

# ---- 3. Poky ----
# top directory は「実行したディレクトリ/bitbake-builds」（bitbake-setup の既定）
if [ ! -f bitbake-builds/$SETUP_CONFIG/build/init-build-env ]; then
    bitbake-setup init --non-interactive $SETUP_CONFIG poky distro/poky machine/qemuarm64
fi

# ---- 4. 自作レイヤー ----
. ./env.sh
# init が最後のフラグメントの設定で止まっていたら（パッケージが足りなかったときなど）、やり直す
[ -n "$(lab_machine)" ] ||
    bitbake-config-build enable-fragment distro/poky machine/qemuarm64
for layer in meta-practice meta-practice-bsp; do
    if ! grep -q "$TOP/$layer[ \"]" conf/bblayers.conf; then
        bitbake-layers add-layer "$TOP/$layer"
    fi
done
bitbake-config-build enable-fragment practice/lowmem
# Wrynose の既定では root でログインできない。学習用なので、パスワードなしの root ログインを有効にする
bitbake-config-build enable-fragment core/yocto/root-login-with-empty-password

echo
echo "== できた。次は ./build.sh =="
