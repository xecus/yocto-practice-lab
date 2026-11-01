# 1 章: Poky をビルドして runqemu で起動する

`bitbake-setup` で Wrynose の Poky を用意し、`core-image-minimal` をビルドして QEMU で起動する。
aarch64-boot-lab の `./run.sh direct`（QEMU → カーネル → `/init`）に相当する。

以下は、特に断りがなければリポジトリのトップ（`~/yocto-practice`）で作業する。

この章の手順は、スクリプトでまとめて実行できる。

```sh
./setup.sh     # 1〜3 と、4 のフラグメントの設定
./build.sh     # 4 のビルド（ログは logs/build-core-image-minimal-qemuarm64.log）
./run.sh direct   # 5 の起動（ログは logs/boot-direct-core-image-minimal-qemuarm64-cortex-a57-smp4.log）
```

以下では、スクリプトが中で何をしているかを順に見る。

## Wrynose で変わったこと

Scarthgap（5.0）までの資料と手順が違う。

| | Scarthgap まで | Wrynose |
|---|---|---|
| ソースの取得 | `git clone git://git.yoctoproject.org/poky` | `bitbake-setup init`（bitbake・openembedded-core・meta-yocto を別々に取得する） |
| ビルド環境の初期化 | `source poky/oe-init-build-env` | `source <setup>/build/init-build-env` |
| `MACHINE` / `DISTRO` の設定 | `conf/local.conf` に書く | `bitbake-config-build enable-fragment machine/<名前>` で `conf/toolcfg.conf` に追加する（フラグメント） |
| root でのログイン | `debug-tweaks` を `EXTRA_IMAGE_FEATURES` に入れる | `debug-tweaks` はない。フラグメント `core/yocto/root-login-with-empty-password` を有効にする |
| `runqemu qemuarm64` | 動く | **エラーになる**。MACHINE の名前を付けずに `runqemu` と打つ（5 で説明する） |

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

### フラグメントを 2 つ足す

`setup.sh` は、自作のレイヤー（`meta-practice`・`meta-practice-bsp`）を `conf/bblayers.conf` に足し、次の 2 つのフラグメントを有効にする。

```sh
bitbake-config-build enable-fragment practice/lowmem
bitbake-config-build enable-fragment core/yocto/root-login-with-empty-password
```

```
OE_FRAGMENTS += "distro/poky machine/qemuarm64 practice/lowmem core/yocto/root-login-with-empty-password"
```

| フラグメント | ファイル | 中身 |
|---|---|---|
| `practice/lowmem` | `meta-practice/conf/fragments/lowmem.conf` | `BB_NUMBER_THREADS = "2"`、`PARALLEL_MAKE = "-j 2"` |
| `core/yocto/root-login-with-empty-password` | `openembedded-core/meta/conf/fragments/yocto/root-login-with-empty-password.conf` | `EXTRA_IMAGE_FEATURES += "allow-empty-password empty-root-password allow-root-login"` |

- `practice/lowmem`: RAM 7GB では、既定（CPU の数）のままだと gcc やカーネルのビルドでメモリが足りなくなるおそれがある。`BB_NUMBER_THREADS` は同時に走らせる BitBake のタスクの数、`PARALLEL_MAKE` は 1 つのタスクの中の `make -j`
- `core/yocto/root-login-with-empty-password`: これがないと、起動しても `root` でログインできない（`Login incorrect`）。学習用なので有効にする。製品には使わない
- フラグメントの名前は「レイヤーのコレクション名/`conf/fragments/` の下のパス」。`practice` は `meta-practice/conf/layer.conf` の `BBFILE_COLLECTIONS`、`core` は openembedded-core の `meta`。作り方は 3 章で見る
- 一覧は `bitbake-config-build list-fragments`
- フラグメントは `local.conf` のあとに読まれるので、`local.conf` に同じ変数を書いても、フラグメントの値が使われる

> この章の最初のビルドは、`local.conf` に `BB_NUMBER_THREADS` と `PARALLEL_MAKE` を直接書いて実行した。そのあとフラグメントに移した。値は同じなので、sstate はそのまま使える。

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

1 つの変数だけなら `bitbake-getvar` のほうが速い。

```sh
$ bitbake-getvar -q --value BB_NUMBER_THREADS
2
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

### 結果

```
start 2026-11-01 02:40:42
...
NOTE: Tasks Summary: Attempted 4331 tasks of which 0 didn't need to be rerun and all succeeded.

Summary: There were 3 WARNING messages.
end 2026-11-01 10:53:14
exit=0
```

**8 時間 12 分**かかった（4 コア、RAM 7GB、並列数 2）。

- WARNING の 3 つは、どれも `Failed to fetch URL ..., attempting MIRRORS if available`（gmp、lzlib、libsdl2）。本家のサーバーから取れず、Yocto のミラーから取った。ビルドには影響しない

時間がかかったレシピ（`tmp/buildstats/` のタスクごとの `Elapsed time` を足したもの。並列に走るので、合計は 8 時間より長い）:

| レシピ | 時間 |
|---|---|
| `llvm-native` 22.1.8 | 166 分 |
| `clang-native` 22.1.8 | 136 分 |
| `linux-yocto` 6.18.54 | 62 分 |
| `gcc` 15.3.0（ターゲット向け） | 49 分 |
| `cmake-native` 4.3.1 | 24 分 |
| `gcc-cross-aarch64` 15.3.0 | 24 分 |
| `qemu-system-native` 10.2.0 | 18 分 |
| 合計（273 レシピ） | 840 分 |

半分以上が **LLVM と clang（ホスト向け）**。イメージには入っていない。`runqemu` が使う `qemu-system-native` の画面の機能から引き込まれている。

```
qemu-system-native  PACKAGECONFIG に virglrenderer epoxy sdl（GPU を使った画面）
  → mesa-native     PACKAGECONFIG に gallium-llvm libclc
    → llvm-native, clang-native
```

この章の起動は `nographic` で画面を使わないので、本当は要らない。依存関係の追い方は 2 章で見る。

`tmp/buildstats/` の時刻で見ると、カーネルは 08:43、rootfs の ext4（`.ext4.zst`）は 08:45 にできていた。そのあとの約 2 時間は、`clang-native`（〜10:08）→ `mesa-native`（〜10:34）→ `qemu-system-native`（〜10:53）を待っていた。イメージのタスクの最後（`do_image_complete`）は、`runqemu` で使う QEMU ができるまで終わらない。

> **時間を短くするには**: openembedded-core には、Yocto Project がビルドした sstate を取ってくるフラグメント `core/yocto/sstate-mirror-cdn` がある（`SSTATE_MIRRORS` を `http://sstate.yoctoproject.org/` にする）。設定と layers のコミットが公式のビルドと合っていれば、ダウンロードで済むタスクが増える。このリポジトリでは、ビルドの中身を見るために使っていない。

### 2 回目のビルド

何も変えずにもう一度ビルドすると、11 秒で終わる。

```
Sstate summary: Wanted 0 Local 0 Mirrors 0 Missed 0 Current 2287 (0% match, 100% complete)
NOTE: Tasks Summary: Attempted 4331 tasks of which 4331 didn't need to be rerun and all succeeded.
```

- `Current 2287`: 2287 個のタスクの結果が、すでに `tmp/` にあって最新
- 自作のレイヤーにまだレシピがないので、`No bb files in default matched BBFILE_PATTERN_practice` の WARNING が出る（`practice-bsp` も）。3 章でレシピを置くと消える

root ログインのフラグメントを足したあとは、イメージを作るタスクだけがやり直しになった（1 分半）。

```
Sstate summary: Wanted 5 Local 0 Mirrors 0 Missed 5 Current 2282 (0% match, 99% complete)
NOTE: Tasks Summary: Attempted 4331 tasks of which 4318 didn't need to be rerun and all succeeded.
```

### ディスク

| 場所 | 大きさ | 中身 |
|---|---|---|
| `bitbake-builds/poky-wrynose/build/tmp/` | 62GB | 作業ディレクトリ（`work/` が 56GB）とできたもの |
| `bitbake-builds/.bitbake-setup-downloads/` | 6.2GB | 取得したソース（`DL_DIR`） |
| `bitbake-builds/.sstate-cache/` | 4.3GB | sstate（`SSTATE_DIR`） |
| `bitbake-builds/poky-wrynose/layers/` | 73MB | bitbake・openembedded-core・meta-yocto など |
| 合計 | 73GB | |

- `DL_DIR` と `SSTATE_DIR` は `bitbake-builds/site.conf` で設定されている。`bitbake-setup` で別の設定を作っても共有される
- `tmp/work/` で大きいのは `gcc`（7GB）、`qemu-system-native`（5GB）、`linux-yocto`（4.6GB）、`openssl`（3GB）

### できたもの

`tmp/deploy/images/qemuarm64/`:

| ファイル | 大きさ | 中身 | aarch64-boot-lab で対応するもの |
|---|---|---|---|
| `Image` | 23MB | カーネル | `linux-6.18.53/arch/arm64/boot/Image`（50MB） |
| `modules-qemuarm64.tgz` | 72MB | カーネルモジュール | — |
| `core-image-minimal-qemuarm64.rootfs.ext4.zst` | 5.8MB（展開すると 23MB） | rootfs | `busybox/rootfs.img`（2.2MB） |
| `core-image-minimal-qemuarm64.rootfs.tar.zst` | 5.8MB | rootfs の tar | — |
| `core-image-minimal-qemuarm64.rootfs.manifest` | | イメージに入ったパッケージの一覧 | — |
| `core-image-minimal-qemuarm64.rootfs.qemuboot.conf` | | `runqemu` が読む設定 | `run.sh` の QEMU の引数 |
| `core-image-minimal-qemuarm64.rootfs.spdx.json` | 1.8MB | SBOM（ソフトウェアの部品表） | — |

- `Image` などはシンボリックリンクで、実体にはビルドの日時が付いている（`Image--6.18.54+git0+366edfd67e_8372c22a7d-r0-qemuarm64-20261031174142.bin`）
- manifest には 32 個のパッケージがある。BusyBox のほかに、`sysvinit`、`eudev`、`glibc`（`libc6`）、`kmod`、`openssl` のライブラリなど

## 5. 起動する

### runqemu に MACHINE の名前を付けない

これまでの資料では `runqemu qemuarm64 nographic` と書くことが多い。Wrynose で machine/ フラグメントを使っていると、これはエラーになる。

```
runqemu - INFO - Running MACHINE=qemuarm64 bitbake -e  ...
ERROR: A builtin fragment 'machine/qemuarm64' is used while MACHINE has already got an assignment.
Please either disable the fragment or remove the value assignment.
```

`runqemu` は、MACHINE の名前を受け取ると `MACHINE=qemuarm64 bitbake -e` で設定を調べる。環境変数の `MACHINE` と、フラグメントの `machine/qemuarm64` の両方があるので、BitBake が止める。

次のどちらかにする。

```sh
runqemu nographic slirp snapshot                       # 今のビルドの MACHINE を使う（bitbake -e を実行する）
runqemu tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.rootfs.qemuboot.conf nographic slirp snapshot
                                                       # qemuboot.conf を直接渡す（bitbake -e を実行しない）
```

`run.sh` は 2 つ目の方法を使う。`bitbake -e` を待たなくてよく、`-m` でほかの MACHINE のイメージも起動できる。

### オプション

| オプション | 意味 |
|---|---|
| `nographic` | 画面を使わず、シリアルを端末につなぐ |
| `slirp` | ユーザーモードのネットワーク。`tap` と違って sudo が要らない |
| `snapshot` | ゲストでの書き込みを捨てる（QEMU の `-snapshot`） |

`snapshot` は、qemuarm64 では必須。イメージが `ext4.zst`（圧縮）しかなく、`runqemu` は `.zst` を `snapshot` のときだけ受け付ける。

```
runqemu - ERROR - .zst images are only supported with snapshot mode. You can either use the "snapshot" option or use an uncompressed image.
```

`snapshot` を付けると、`runqemu` は `.ext4.zst` を同じディレクトリに展開し、終了するときに消す。

```
runqemu - INFO - Decompressing .../core-image-minimal-qemuarm64.rootfs-20261101020436.ext4.zst to .../core-image-minimal-qemuarm64.rootfs-20261101020436.ext4
...
runqemu - INFO - Removing .../core-image-minimal-qemuarm64.rootfs-20261101020436.ext4
```

QEMU を `kill` などで止めると、展開したファイルが残る。`tmp/deploy/images/qemuarm64/` に `.ext4` が残っていたら消してよい。

### QEMU のコマンドライン

`runqemu` が実行したコマンド（`logs/boot-direct-*.log` の `runqemu - INFO - Running` の行。パスは短くした）:

```
qemu-system-aarch64
  -device virtio-net-pci,netdev=net0,mac=52:54:00:12:35:02
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:2323-:23,tftp=.../deploy/images/qemuarm64
  -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0
  -drive id=disk0,file=.../core-image-minimal-qemuarm64.rootfs-20261101020436.ext4,if=none,format=raw
  -device virtio-blk-pci,drive=disk0
  -device qemu-xhci -device usb-tablet -device usb-kbd
  -machine virt -cpu cortex-a57 -smp 4 -m 256
  -snapshot
  -serial mon:stdio -serial null -nographic
  -device virtio-gpu-pci
  -kernel .../deploy/images/qemuarm64/Image
  -append 'root=/dev/vda rw  mem=256M ip=dhcp console=ttyAMA0 console=hvc0 swiotlb=0 '
```

- QEMU は `tmp/work/x86_64-linux/qemu-helper-native/1.0/recipe-sysroot-native/usr/bin/qemu-system-aarch64`。Yocto がビルドした 10.2.0 で、ホストの QEMU は使わない
- 値は `qemuboot.conf` から来ている（`qb_machine = -machine virt`、`qb_cpu = -cpu cortex-a57`、`qb_smp = -smp 4`、`qb_mem = -m 256`、`qb_kernel_cmdline_append = swiotlb=0` など）
- `hostfwd`: ホストの 2222 番をゲストの 22 番（ssh）につなぐ。`core-image-minimal` には ssh のサーバーが入っていないので、今は使えない

### 起動ログ

```
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x411fd070]
[    0.000000] Linux version 6.18.54-yocto-standard (oe-user@oe-host) (aarch64-poky-linux-gcc (GCC) 15.3.0, GNU ld (GNU Binutils) 2.46.1.20260718) #1 SMP PREEMPT Mon Sep 28 17:58:49 UTC 2026
[    0.000000] Machine model: linux,dummy-virt
...
[    0.157967] SMP: Total of 4 processors activated.
...
[    0.228723] Memory: 224080K/262144K available (14912K kernel code, 2144K rwdata, 3752K rodata, 1856K init, 645K bss, 33492K reserved, 0K cma-reserved)
...
[    2.359437] EXT4-fs (vda): mounted filesystem 8f5ba0f1-074a-4a0b-9cf5-484d9745f371 r/w with ordered data mode. Quota mode: disabled.
[    2.360340] VFS: Mounted root (ext4 filesystem) on device 253:0.
...
[    2.501923] Run /sbin/init as init process
INIT: version 3.14 booting
Starting udev
...
INIT: Entering runlevel: 5
Configuring network interfaces... ip: RTNETLINK answers: File exists
Starting syslogd/klogd: done

Poky (Yocto Project Reference Distro) 6.0.4 qemuarm64 /dev/ttyAMA0

qemuarm64 login: root

WARNING: Poky is a reference Yocto Project distribution that should be used for
testing and development purposes only. It is recommended that you create your
own distribution for production use.

root@qemuarm64:~#
```

- `[0x411fd070]` は MIDR。`0xd07` が Cortex-A57
- コンパイラは Yocto がビルドした `aarch64-poky-linux-gcc` 15.3.0。日付（`Mon Sep 28 17:58:49 UTC 2026`）はソースのコミットの日時で、ビルドした日時ではない（`SOURCE_DATE_EPOCH`。再現できるビルドのため）
- `ip: RTNETLINK answers: File exists`: カーネルが `ip=dhcp` でアドレスを設定したあとに、`/etc/init.d/networking` でもう一度設定しようとして出る、と考えられる（まだ確かめていない）。ログインもネットワークの設定も済んでいる
- ログインのプロンプトまで、QEMU の起動から 7〜8 秒

### ゲストで確かめる

```
root@qemuarm64:~# uname -a
Linux qemuarm64 6.18.54-yocto-standard #1 SMP PREEMPT Mon Sep 28 17:58:49 UTC 2026 aarch64 GNU/Linux
root@qemuarm64:~# cat /proc/cmdline
root=/dev/vda rw  mem=256M ip=dhcp console=ttyAMA0 console=hvc0 swiotlb=0
root@qemuarm64:~# free
              total        used        free      shared  buff/cache   available
Mem:         230508       28212      183540        4132       18756      191448
Swap:             0           0           0
root@qemuarm64:~# df -h /
Filesystem                Size      Used Available Use% Mounted on
/dev/root                20.2M     13.5M      5.1M  73% /
root@qemuarm64:~# ls -l /sbin/init
lrwxrwxrwx    1 root     root            19 Apr  5  2011 /sbin/init -> /sbin/init.sysvinit
```

- `/sbin/init` は sysvinit（`INIT_MANAGER="sysvinit"`）。BusyBox の init ではない
- rootfs の空きは 5.1MB しかない。大きさの決まり方は 7 章で見る
- コマンドの多くは BusyBox（`head -20` のような古い書き方は通らず、`head -n 20` と書く）
- `/etc/os-release` はない（`os-release` パッケージが入っていない）

### 終了する

ゲストで `poweroff`。

```
root@qemuarm64:~# poweroff
...
[   16.154323] reboot: Power down
runqemu - INFO - Cleaning up
```

QEMU ごと止めるなら `Ctrl-a x`（`-serial mon:stdio` なので、aarch64-boot-lab と同じ）。

### CPU と CPU の数を変える

`run.sh` の `-c` と `-s` は、`qemuparams="-cpu ... -smp ..."` を `runqemu` に渡す。`runqemu` は `qemuparams` を最後に付けるので、`qemuboot.conf` の値より優先される。

```sh
./run.sh -c a76 -s 1 direct
```

QEMU のコマンドラインには `-cpu cortex-a57 -smp 4` と `-cpu cortex-a76 -smp 1` の両方が付き、QEMU はあとの方を使う。

```
root@qemuarm64:~# grep -E "processor|CPU part" /proc/cpuinfo
processor       : 0
CPU part        : 0xd0b
```

```
[    0.085885] SMP: Total of 1 processors activated.
```

`0xd0b` は Cortex-A76。cortexa57 向けにコンパイルしたカーネルとユーザーランドが、そのまま動く（`TUNE_FEATURES` は `aarch64 crc cortexa57` で、Armv8.0 と CRC の命令しか使わない。Armv8.2 の A76 はそれを含む）。

## 6. aarch64-boot-lab の `./run.sh direct` と比べる

| | aarch64-boot-lab（`./run.sh direct 6.18`） | Yocto（`./run.sh direct`） |
|---|---|---|
| QEMU | Ubuntu の `qemu-system-aarch64` | Yocto がビルドした 10.2.0 |
| CPU × 数 | cortex-a53 × 1 | cortex-a57 × 4 |
| メモリ | 128MB（QEMU の既定） | 256MB（`qb_mem`） |
| カーネル | 6.18.53、`defconfig`、Ubuntu の gcc 13.3.0 | 6.18.54-yocto-standard、linux-yocto の設定、Yocto の gcc 15.3.0 |
| `Image` | 50MB | 23MB |
| ルート | initramfs（`-initrd rootfs.img`、2.2MB） | ext4 のディスク（`/dev/vda`、23MB） |
| init | `/init`（自分で書いたシェルスクリプト） | `/sbin/init`（sysvinit）→ `/etc/init.d/rcS` → ログイン |
| デバイス | なし（シリアルだけ） | virtio-net・virtio-blk・virtio-rng・virtio-gpu・USB のキーボードとタブレット |
| 起動の手順 | `run.sh` の中で QEMU の引数を組み立てる | `qemuboot.conf`（`QB_*` の変数）から `runqemu` が組み立てる |

- aarch64-boot-lab は「必要なものを自分で 1 つずつ足す」、Yocto は「レシピと MACHINE の設定から全部できる」。同じ QEMU の virt で、同じ 6.18 のカーネルが動いているが、中身はかなり違う
- 2 章からは、Yocto がこれをどうやって作ったかを見ていく
