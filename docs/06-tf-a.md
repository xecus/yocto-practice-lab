# 6 章: TF-A を入れる

aarch64-boot-lab の `./run.sh tfa-uboot-rootdisk`（QEMU → TF-A（BL1 → BL2 → BL31）→ U-Boot → `boot.scr` → カーネル）を Yocto で作る。

> **下書き**: meta-arm（wrynose ブランチ、673e8d7、2026-09-16）のソースを読んで書いた。ビルド・起動はまだ確かめていない。

## 1. meta-arm を追加する

TF-A のレシピ `trusted-firmware-a` は openembedded-core にはなく、**meta-arm** にある。

```sh
cd bitbake-builds/poky-wrynose/layers
git clone -b wrynose https://git.yoctoproject.org/meta-arm
cd ../build
bitbake-layers add-layer ../layers/meta-arm/meta-arm-toolchain
bitbake-layers add-layer ../layers/meta-arm/meta-arm
```

- meta-arm は `meta-arm-toolchain` に依存する（`LAYERDEPENDS_meta-arm = "core arm-toolchain"`）ので、先に追加する
- `LAYERSERIES_COMPAT_meta-arm = "wrynose"`

<!-- TODO: bitbake-setup で管理するレイヤーに足す方法があるか調べる（今は手で clone している） -->

meta-arm の TF-A のレシピ:

| レシピ | 版 |
|---|---|
| `trusted-firmware-a_2.10.30.bb` | v2.10 LTS |
| `trusted-firmware-a_2.12.10.bb` | v2.12 LTS |
| `trusted-firmware-a_2.14.1.bb` | v2.14 |
| `trusted-firmware-a_git.bb` | 開発版 |

aarch64-boot-lab は v2.15.0 を使った。meta-arm wrynose には 2.15 のレシピはない。

## 2. まず meta-arm の qemuarm64-secureboot を動かす

meta-arm には、TF-A + U-Boot で起動する MACHINE `qemuarm64-secureboot` がある。自分で組む前に、これを動かして中身を読む。

```sh
bitbake-config-build enable-fragment machine/qemuarm64-secureboot
bitbake core-image-minimal
runqemu nographic slirp    # MACHINE の名前は付けない（1 章の 5）
```

<!-- TODO: fragment で MACHINE を変えられるか確かめる。だめなら local.conf に MACHINE = を書く -->

### qemuarm64-secureboot.conf

```
MACHINEOVERRIDES =. "qemuarm64:"
require ${COREBASE}/meta/conf/machine/qemuarm64.conf

QB_MACHINE = "-machine virt,secure=on,acpi=off"
QB_MEM = "-m 1024"
QB_DEFAULT_FSTYPE = "wic.qcow2"
QB_DEFAULT_BIOS = "flash.bin"
QB_FSINFO = "wic:no-kernel-in-fs"
QB_ROOTFS_OPT = ""
QB_KERNEL_ROOT = "/dev/vda2"

IMAGE_FSTYPES += "wic wic.qcow2"
WKS_FILE ?= "qemuarm64.wks"
WKS_FILE_DEPENDS:append = " trusted-firmware-a"
IMAGE_BOOT_FILES = "${KERNEL_IMAGETYPE}"

MACHINE_FEATURES += "optee-ftpm"
```

aarch64-boot-lab で分かったことと比べる:

| | aarch64-boot-lab | qemuarm64-secureboot |
|---|---|---|
| QEMU の `-M` | `virt,secure=on,virtualization=on` | `virt,secure=on,acpi=off`（**`virtualization=on` がない**） |
| メモリ | `-m 1024`（BL2 が U-Boot を `0x60000000` に置くため） | `-m 1024`。U-Boot も `CONFIG_SYS_TEXT_BASE=0x60000000`（`u-boot/qemuarm64.cfg`） |
| ファームウェア | `qemu_fw.bios`（`bl1.bin` の後ろに `fip.bin` を連結） | `flash.bin`（`bl1.bin` を先頭に、`fip.bin` を 256KB の位置に `dd`） |
| BL33 | U-Boot | U-Boot（`TFA_UBOOT = "1"` → `BL33=${DEPLOY_DIR_IMAGE}/u-boot.bin`） |
| BL32（Secure OS） | なし | **OP-TEE**（`TFA_SPD = "opteed"`。`optee-os` の `tee-*_v2.bin` を `BL32` として FIP に入れる） |
| CPU | 選べる（a53 / a55 / a72 / a76 / a710） | cortex-a57（qemuarm64 のまま） |
| ブートの設定 | `boot.scr` | extlinux（wic の `bootloader --configfile`） |

見どころ:
- `QB_FSINFO = "wic:no-kernel-in-fs"` があり、`QB_DEFAULT_KERNEL = "none"` はない。runqemu の仕組み（5 章）からすると、`-kernel` も付くはず。そのとき U-Boot が fw_cfg のカーネルと extlinux のどちらで起動するかを確かめる
- **`virtualization=on` がないので、Linux は EL1 で動くはず**（aarch64-boot-lab の TF-A 版は EL2）。dmesg の `CPU: All CPU(s) started at EL1` / `EL2` で確かめる
- OP-TEE も一緒にビルドされるので、ビルドは重くなる

<!-- TODO: 起動ログを保存。EL、PSCI、poweroff 時の表示を aarch64-boot-lab と比べる。ビルド時間とメモリ -->

## 3. 自分で組む: OP-TEE なし、aarch64-boot-lab と同じ構成

aarch64-boot-lab と同じ「TF-A → U-Boot → Linux（EL2）」にするため、qemuarm64-secureboot を元に自分の MACHINE を作る（8 章の MACHINE の先取り）。

`meta-practice-bsp/conf/machine/qemuarm64-tfa.conf`（案）:

```
MACHINEOVERRIDES =. "qemuarm64:qemuarm64-secureboot:"
require ${COREBASE}/meta/conf/machine/qemuarm64.conf

QB_MACHINE = "-machine virt,secure=on,virtualization=on,acpi=off"
QB_MEM = "-m 1024"
QB_DEFAULT_BIOS = "flash.bin"
...
```

- `MACHINEOVERRIDES` に `qemuarm64-secureboot` を入れると、meta-arm の bbappend（`:qemuarm64-secureboot`）がそのまま効く
- OP-TEE は 2 か所から入ってくる。MACHINE の設定だけでは外せない
  - `trusted-firmware-a-qemuarm64-secureboot.inc` が `TFA_SPD` を `=` で `opteed` にする（レシピの中の代入なので、MACHINE の `TFA_SPD = ""` は上書きされる）
  - `trusted-firmware-a_%.bbappend` が、QEMU のマシン（`qemuall`）なら `DEPENDS:append = " optee-os"` と `EXTRA_OEMAKE:append` の `BL32=...` を足す。`qemuarm64-secureboot` を入れなくても、`qemuarm64.conf` を require すれば `qemuall` になるので足される
- そのため、`meta-practice-bsp` に `trusted-firmware-a_%.bbappend` を作り、`TFA_SPD = ""`、`DEPENDS:remove = "optee-os"`、`EXTRA_OEMAKE:remove` で `BL32=...` を消す。`MACHINE_FEATURES` からは `optee-ftpm` を外す
- `virtualization=on` を足して、Linux が EL2 で動くかを見る

<!-- TODO: この案で動くか確かめる。OVERRIDES の書き方は試して直す -->

## 4. TF-A のデバッグ版とリリース版

aarch64-boot-lab では、cortex-a55 / a76 / a710 でデバッグ版の TF-A が BL1 で止まった（`CLUSTERIDR_EL1` を QEMU が実装していないため）。

meta-arm では `TFA_DEBUG ?= "${FIRMWARE_DEBUG_BUILD}"` で切り替える。ビルドの出力は `BUILD_DIR` の `debug` / `release` に分かれる。

8 章で CPU を cortex-a76 などに変えたときに、同じ問題が出るかを確かめる。

<!-- TODO: FIRMWARE_DEBUG_BUILD の既定値を bitbake -e で確かめる -->
