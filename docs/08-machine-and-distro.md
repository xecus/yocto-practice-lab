# 8 章: 独自の MACHINE と DISTRO

5〜7 章で `local.conf` に書いた設定を、自分の MACHINE と DISTRO にまとめる。
aarch64-boot-lab の `select-cpu.sh`（CPU を cortex-a53 / a55 / a72 / a76 / a710 から選ぶ）を、MACHINE の切り替えで再現する。

> **下書き**: qemuarm64.conf の中身はソースで確かめた。自分の MACHINE・DISTRO はまだ書いていない。

## 1. MACHINE と DISTRO の役割

| | 決めるもの | 例 |
|---|---|---|
| MACHINE | ハードウェアに関すること | CPU とコンパイラの最適化（tune）、カーネル、ブートローダー、シリアル、イメージの形式、QEMU の起動オプション |
| DISTRO | ハードウェアに依存しない方針 | init（sysvinit / systemd）、C ライブラリ、`DISTRO_FEATURES`、パッケージ形式 |
| イメージ | 何を入れるか | `core-image-minimal` |

## 2. qemuarm64.conf を読む

`openembedded-core/meta/conf/machine/qemuarm64.conf`:

```
require conf/machine/include/arm/armv8a/tune-cortexa57.inc
require conf/machine/include/qemu.inc

KERNEL_IMAGETYPE = "Image"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot"
UBOOT_MACHINE ?= "qemu_arm64_defconfig"
SERIAL_CONSOLES ?= "115200;ttyAMA0 115200;hvc0"

QB_SYSTEM_NAME = "qemu-system-aarch64"
QB_MACHINE = "-machine virt"
QB_CPU = "-cpu cortex-a57"
QB_SMP ?= "-smp 4"
...
```

- コンパイラの最適化（`tune-cortexa57.inc`）と、QEMU の CPU（`QB_CPU`）は別の設定
- `QB_SMP ?= "-smp 4"`: 1 章の起動は 4 CPU（aarch64-boot-lab の既定は 1）

## 3. 自分の MACHINE を作る

`meta-practice/conf/machine/` に、aarch64-boot-lab の CPU に合わせた MACHINE を作る。

```
# meta-practice/conf/machine/practice-a72.conf（案）
require conf/machine/qemuarm64.conf
MACHINEOVERRIDES =. "qemuarm64:"

DEFAULTTUNE = "cortexa72-nocrypto"
require conf/machine/include/arm/armv8a/tune-cortexa72.inc
QB_CPU = "-cpu cortex-a72"
QB_SMP = "-smp 1"
```

- `MACHINEOVERRIDES` に `qemuarm64` を入れるのは、linux-yocto の `COMPATIBLE_MACHINE` と `KBRANCH:qemuarm64` を効かせるため（MACHINE の名前が違うので、そのままでは `qemuarm64` にならない）

<!-- TODO: tune-*.inc をあとから require して DEFAULTTUNE が切り替わるか確かめる。だめなら qemuarm64.conf を require せず、中身を写す -->

作る MACHINE（案）:

| MACHINE | tune | QB_CPU | aarch64-boot-lab |
|---|---|---|---|
| `practice-a53` | cortexa53（`armv8a/tune-cortexa53.inc`） | cortex-a53 | `--cpu a53`（既定） |
| `practice-a55` | cortexa55（`armv8-2a/tune-cortexa55.inc`） | cortex-a55 | `--cpu a55` |
| `practice-a72` | cortexa72-nocrypto（`armv8a/tune-cortexa72.inc`） | cortex-a72 | `--cpu a72` |
| `practice-a76` | cortexa76（`armv8-2a/tune-cortexa76.inc`） | cortex-a76 | `--cpu a76` |
| `practice-a710` | cortexa710（`armv9a/tune-cortexa710.inc`） | cortex-a710 | `--cpu a710` |

チューニングのファイルは `openembedded-core/meta/conf/machine/include/arm/` にあり、aarch64-boot-lab の 5 つの CPU はすべてそろっている。

RAM 7GB では、5 つすべてでユーザーランドをビルドし直すのは時間がかかる。まず **a72 と a76** の 2 つでやる。tune を 11・12 章の Raspberry Pi に合わせる（Pi 4 は `cortexa72-nocrypto`、Pi 5 は `cortexa76`）と、ユーザーランドのビルド結果を使い回せるかもしれない。

<!-- TODO: practice-a72 の DEFAULTTUNE を cortexa72-nocrypto にしたとき、raspberrypi4-64 で sstate がどれだけ使われるか確かめる -->

### MACHINE を切り替える

```sh
bitbake-config-build enable-fragment machine/practice-a72
bitbake core-image-minimal
```

<!-- TODO: 自分のレイヤーの MACHINE が machine/ フラグメントとして使えるか確かめる（OE_FRAGMENTS_BUILTIN = "machine:MACHINE distro:DISTRO"） -->

## 4. 何がビルドし直しになるか

tune が変わると、ターゲット向けのパッケージ（glibc、BusyBox など）は**すべて**ビルドし直しになる（`tmp/work/cortexa72-poky-linux/` のように、アーキのディレクトリが変わる）。ホスト向けのツール（`-native`、クロスコンパイラの大部分）は再利用される。

```sh
bitbake core-image-minimal 2>&1 | grep 'Sstate summary'
```

<!-- TODO: cortexa57 → cortexa72-nocrypto のときの Sstate summary とビルド時間。アーキのディレクトリ名（-nocrypto が付くか）も確かめる -->

QEMU の CPU（`QB_CPU`）だけ変えるなら、ビルドし直しは不要。

```sh
runqemu qemuarm64 nographic slirp qemuparams="-cpu cortex-a76"
```

<!-- TODO: qemuparams の -cpu が QB_CPU より優先されるか確かめる -->

## 5. CPU による違いを確かめる

aarch64-boot-lab で見たものと同じものを見る。

- `Booting Linux on physical CPU 0x0000000000 [0x410fd034]` の MIDR
- `CPU features: detected: ...` の一覧
- cortexa57 向けのバイナリを cortex-a53 で動かしても問題ないこと（どちらも ARMv8.0）と、cortexa76 向けのバイナリを cortex-a53 で動かすとどうなるか（ARMv8.2 の命令を使っていれば `Illegal instruction`）

<!-- TODO: 最後の実験。実際に止まるかは確かめる -->

## 6. 自分の DISTRO を作る

```
# meta-practice/conf/distro/practice.conf（案）
require conf/distro/poky.conf
DISTRO = "practice"
DISTRO_NAME = "yocto-practice"
DISTRO_VERSION = "0.1"
```

### init を systemd に変えて比べる

openembedded-core の `meta/conf/distro/include/` に、init の設定が 3 つある。

| ファイル | init |
|---|---|
| `init-manager-sysvinit.inc` | sysvinit（Poky の既定） |
| `init-manager-systemd.inc` | systemd |
| `init-manager-mdev-busybox.inc` | BusyBox の init と mdev（aarch64-boot-lab の rootdisk 版に近い） |

```
INIT_MANAGER = "systemd"
```

比べること:
- 起動時間（カーネルの起動からログインまで）
- イメージの大きさ（`*.manifest` のパッケージ数）
- ビルドし直しの量

`INIT_MANAGER = "mdev-busybox"` にすると、aarch64-boot-lab の rootdisk 版（BusyBox の init、`inittab`、`rcS`）に近くなる。3 つを並べて比べる。

<!-- TODO: 3 つの起動時間・大きさの表 -->
