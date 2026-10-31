# 1 章: Poky をビルドして runqemu で起動する

`bitbake-setup` で Wrynose の Poky を用意し、`core-image-minimal` をビルドして QEMU で起動する。
aarch64-boot-lab の `./run.sh direct`（QEMU → カーネル → `/init`）に相当する。

> **下書き**: 「4. ビルド」の結果と「5. 起動」はまだ確かめていない。確かめたら書き直す。

以下は、特に断りがなければリポジトリのトップ（`~/yocto-practice`）で作業する。

## Wrynose で変わったこと

Scarthgap（5.0）までの資料と手順が違う。

| | Scarthgap まで | Wrynose |
|---|---|---|
| ソースの取得 | `git clone git://git.yoctoproject.org/poky` | `bitbake-setup init`（bitbake・openembedded-core・meta-yocto を別々に取得する） |
| ビルド環境の初期化 | `source poky/oe-init-build-env` | `source <setup>/build/init-build-env` |
| `MACHINE` / `DISTRO` の設定 | `conf/local.conf` に書く | `bitbake-config-build enable-fragment machine/<名前>` で `conf/toolcfg.conf` に追加する（フラグメント） |

## 1. パッケージ

```sh
sudo apt-get install build-essential chrpath cpio debianutils diffstat file gawk gcc git \
    iputils-ping libacl1 libcrypt-dev locales python3 python3-git python3-jinja2 \
    python3-pexpect python3-pip python3-subunit socat texinfo unzip wget xz-utils zstd \
    python3-websockets lz4
```

- 1 行目から `zstd` までは [System Requirements](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html) の Ubuntu / Debian 向けの一覧
- `python3-websockets` は、Debian 11 と Ubuntu 22.04 以外では別に入れるよう書かれている（共有 sstate の取得に使う）
- `en_US.UTF-8` ロケールが必要。`locale -a | grep en_US.utf8` で確かめる
- QEMU はホストに入れなくてよい。Yocto が `qemu-system-native` を自分でビルドし、`runqemu` はそれを使う

足りないと、`bitbake-setup init` の最後で次のように止まる。

```
ERROR: The following required tools (as specified by HOSTTOOLS) appear to be unavailable in PATH, please install them in order to proceed:
  chrpath diffstat gawk
```

## 2. ユーザー名前空間を許可する（Ubuntu 24.04）

BitBake は、タスクの実行中にネットワークを使わせないためにユーザー名前空間を使う。Ubuntu 24.04 は AppArmor で非特権ユーザーのユーザー名前空間を制限しているので、そのままでは使えない。

```sh
$ sysctl kernel.apparmor_restrict_unprivileged_userns
kernel.apparmor_restrict_unprivileged_userns = 1
$ unshare --user --map-root-user true
unshare: write failed /proc/self/uid_map: Operation not permitted
```

制限を外す。

```sh
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/60-bitbake-userns.conf
sudo sysctl --system | grep userns
```

```
kernel.apparmor_restrict_unprivileged_userns = 0
* Applying /etc/sysctl.d/60-bitbake-userns.conf ...
kernel.apparmor_restrict_unprivileged_userns = 1
kernel.unprivileged_userns_clone = 1
kernel.apparmor_restrict_unprivileged_userns = 0
```

- 1 行目は `tee` の出力。`= 1` の行は Ubuntu 標準の `/usr/lib/sysctl.d/10-apparmor.conf` が設定したもの
- `sysctl --system` はファイル名の順に読むので、`10-apparmor.conf` の `1` を `60-bitbake-userns.conf` の `0` が上書きする。再起動しても `0` のまま
- `sysctl kernel.apparmor_restrict_unprivileged_userns` で `0` になっていることを確かめる
- `unshare --user --map-root-user true` が成功すれば OK
- システム全体の制限を外す設定。元に戻すときは `/etc/sysctl.d/60-bitbake-userns.conf` を消して `sudo sysctl --system`

## 3. bitbake-setup で Poky を用意する

`bitbake-setup` を venv に入れる。

```sh
python3 -m venv --clear ./bitbake-setup-venv
. ./bitbake-setup-venv/bin/activate
pip install bitbake-setup
```

選べる設定を見る。

```sh
$ bitbake-setup list
...
poky-wrynose	Poky - The Yocto Project testing distribution configurations and hardware test platforms, release 6.0 'wrynose' (supported until 2030-05-31)
...
```

`poky-wrynose` を、DISTRO `poky`、MACHINE `qemuarm64` で初期化する。

```sh
bitbake-setup init --non-interactive poky-wrynose poky distro/poky machine/qemuarm64
```

- 引数なしの `bitbake-setup init` は対話式で、設定・MACHINE・DISTRO を番号で選ぶ
- top directory の既定は「実行したディレクトリ/`bitbake-builds`」。`bitbake-setup settings list` で確かめられる
- 取得したレイヤー

| レイヤー | ブランチ | コミット |
|---|---|---|
| bitbake | 2.18 | 6e260eb6a (2026-10-07) |
| openembedded-core | wrynose | ae5a301091 (2026-10-27) |
| meta-yocto | wrynose | 79b6d870 (2026-10-15) |
| yocto-docs | wrynose | 197ed05f4 (2026-10-23) |

`conf/bblayers.conf` に入るのは `openembedded-core/meta`・`meta-yocto/meta-yocto-bsp`・`meta-yocto/meta-poky` の 3 つ。

パッケージが足りなくて init の最後で止まったときは、パッケージを入れてから、フラグメントの設定だけやり直せばよい。

```sh
cd bitbake-builds/poky-wrynose/build
. ./init-build-env
bitbake-config-build enable-fragment distro/poky machine/qemuarm64
```

```
Fragment distro/poky added to .../build/conf/toolcfg.conf.
Fragment machine/qemuarm64 added to .../build/conf/toolcfg.conf.
```

`conf/toolcfg.conf` は次のようになる。

```
OE_FRAGMENTS += "distro/poky machine/qemuarm64"
```

## 4. ビルド

### 並列数を下げる

`conf/local.conf` に次を足す。RAM 7GB では、既定（CPU の数）のままだと gcc やカーネルのビルドでメモリが足りなくなるおそれがある。

```
BB_NUMBER_THREADS = "2"
PARALLEL_MAKE = "-j 2"
```

- `BB_NUMBER_THREADS`: 同時に走らせる BitBake のタスクの数
- `PARALLEL_MAKE`: 1 つのタスクの中の `make -j`

### 効いている設定を確かめる

`bitbake -e` は、すべての設定ファイルを読んだあとの変数の値を出す。

```sh
$ bitbake -e | grep -E '^(MACHINE|DISTRO|DISTRO_VERSION|BB_NUMBER_THREADS|PARALLEL_MAKE|INIT_MANAGER|PREFERRED_PROVIDER_virtual/kernel|PREFERRED_VERSION_linux-yocto|TCLIBC)='
BB_NUMBER_THREADS="2"
DISTRO="poky"
DISTRO_VERSION="6.0.4"
INIT_MANAGER="sysvinit"
MACHINE="qemuarm64"
PARALLEL_MAKE="-j 2"
PREFERRED_PROVIDER_virtual/kernel="linux-yocto"
PREFERRED_VERSION_linux-yocto="6.18%"
TCLIBC="glibc"
```

### ビルドする

```sh
bitbake core-image-minimal
```

最初に表示される Build Configuration:

```
BB_VERSION           = "2.18.0"
BUILD_SYS            = "x86_64-linux"
NATIVELSBSTRING      = "ubuntu-24.04"
TARGET_SYS           = "aarch64-poky-linux"
MACHINE              = "qemuarm64"
SDKMACHINE           = "x86_64"
DISTRO               = "poky"
DISTRO_VERSION       = "6.0.4"
TUNE_FEATURES        = "aarch64 crc cortexa57"
meta                 = "wrynose:ae5a301091f5b0574ea7444aab40b309b6d9f3f2"
meta-yocto-bsp
meta-poky            = "wrynose:79b6d87030178bed0088ad3b00aa6dfbabac37c4"
```

- `TARGET_SYS = "aarch64-poky-linux"`: aarch64-boot-lab では Ubuntu の `aarch64-linux-gnu-gcc` を使ったが、Yocto はクロスコンパイラも自分でビルドする
- `TUNE_FEATURES` の `cortexa57`: qemuarm64 は Cortex-A57 向けにコンパイルする（aarch64-boot-lab の既定の CPU は cortex-a53）
- 最初のビルドは sstate が空なので、何も再利用できない。`Sstate summary: Wanted 2287 Local 0 Mirrors 0 Missed 2287` は「sstate から取り出したいタスク 2287 個のうち、見つかったのは 0 個」という意味。実行するタスクは全部で 4331 個（`Running task 188 of 4331`）

<!-- TODO: ビルド時間、ディスク使用量、できたファイル（tmp/deploy/images/qemuarm64/）を書く -->

## 5. 起動する

<!-- TODO: runqemu qemuarm64 nographic で起動し、確かめた内容を書く
- 起動ログ（logs/ に保存）
- aarch64-boot-lab の ./run.sh direct 6.18 との比較（QEMU のコマンドライン、カーネルのバージョン、CPU、起動時間、init）
- 終了方法
-->
