# 5 章: U-Boot を入れる

aarch64-boot-lab の `./run.sh uboot-rootdisk`（QEMU → U-Boot → rootdisk の p1 の `boot.scr` → カーネル → `/dev/vda2`）を Yocto で作る。

> **下書き**: レシピ・runqemu の仕組みはソースで確かめた。組み合わせ方（このあとの「3」以降）はまだ試していない。うまくいかなければ書き直す。

## 1. 1 章の起動との違い

1 章の `runqemu qemuarm64` は、QEMU の `-kernel` にカーネルを直接渡していた（aarch64-boot-lab の `direct`）。U-Boot を通すには、次の 4 つが必要。

| 必要なもの | aarch64-boot-lab | Yocto |
|---|---|---|
| U-Boot 本体 | `u-boot/u-boot.bin`（`qemu_arm64_defconfig`） | `u-boot` レシピ（`u-boot_2026.01.bb`） |
| ブートスクリプト | `boot/boot-rootdisk.cmd` → `mkimage` → `boot.scr` | `UBOOT_ENV` 変数で `u-boot` レシピに作らせる、または wic の extlinux |
| p1 にカーネルと `boot.scr`、p2 に rootfs のディスク | `make-rootdisk.sh` | wic（7 章を先に少し使う） |
| QEMU に `-bios u-boot.bin` を渡し、`-kernel` は渡さない | `run.sh` | `qemuboot.conf` の `QB_DEFAULT_BIOS` と `QB_DEFAULT_KERNEL` |

## 2. qemuarm64 の U-Boot はもう設定されている

`openembedded-core/meta/conf/machine/qemuarm64.conf`:

```
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot"
UBOOT_MACHINE ?= "qemu_arm64_defconfig"
```

aarch64-boot-lab と同じ `qemu_arm64_defconfig`。ただし版は v2024.01 ではなく **2026.01**。core-image-minimal は U-Boot に依存しないので、1 章ではビルドされていない。

```sh
bitbake u-boot
ls -l tmp/deploy/images/qemuarm64/u-boot*
```

<!-- TODO: できたファイル。aarch64-boot-lab の configs/u-boot-v2024.01.config と .config を比べる -->

## 3. ブートスクリプトを作る

`u-boot.inc` は、`UBOOT_ENV` を設定すると `${UBOOT_ENV}.cmd` を `mkimage -T script` で変換して deploy する（`UBOOT_ENV_SUFFIX = "scr"` のとき）。

`meta-practice/recipes-bsp/u-boot/u-boot_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://boot.cmd"
UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"
```

`files/boot.cmd` は aarch64-boot-lab の `boot/boot-rootdisk.cmd` をそのまま使う。カーネルのファイル名（`Image`）・コンソール（`ttyAMA0`）・ルート（`/dev/vda2`）は qemuarm64 でも同じ。

```
setenv bootargs "console=ttyAMA0 root=/dev/vda2 rw rootwait"
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} ${prefix}Image
booti ${kernel_addr_r} - ${fdtcontroladdr}
```

<!-- TODO: Yocto の rootfs は sysvinit なので、console=ttyAMA0 でログインのプロンプトが出るか確かめる -->

## 4. ディスクイメージ（wic）

p1 に `Image` と `boot.scr`、p2 に rootfs を入れる。aarch64-boot-lab の `make-rootdisk.sh` に合わせる（MBR、p1 は 1MiB の位置から 64MiB の ext4、ラベル `boot`）。

`meta-practice/wic/qemuarm64-uboot.wks`:

```
part /boot --source bootimg_partition --ondisk vda --fstype=ext4 --label boot   --active --align 1024 --size 64M
part /     --source rootfs            --ondisk vda --fstype=ext4 --label rootfs --align 1024
```

`local.conf`（あとで 8 章の MACHINE に移す）:

```
IMAGE_FSTYPES += "wic"
WKS_FILE = "qemuarm64-uboot.wks"
IMAGE_BOOT_FILES = "Image boot.scr"
EXTRA_IMAGEDEPENDS += "u-boot"
```

- `bootimg_partition` は `IMAGE_BOOT_FILES` に書いたファイルを `DEPLOY_DIR_IMAGE` から p1 にコピーする
- プラグインの名前は `bootimg_partition`（アンダースコア）。openembedded-core の `sdimage-bootpart.wks` もこの名前。古い資料の `bootimg-partition`（ハイフン）は以前の名前
- `EXTRA_IMAGEDEPENDS` で、イメージを作る前に U-Boot をビルド・deploy させる

<!-- TODO: wic ls で p1 の中身を確かめる -->

### 参考: meta-arm の qemuarm64-secureboot のやり方

6 章で使う meta-arm の `qemuarm64-secureboot` は、`boot.scr` ではなく **extlinux**（`/boot/extlinux/extlinux.conf`）を使っている。

```
# meta-arm/files/wic/qemuarm64.wks
bootloader --ptable gpt --configfile="qemuarm64.cfg"
part /boot --ondisk=vda --align 64 --size=100M --active --source bootimg-partition --fstype=ext4 --label boot --sourceparams="loader=u-boot"
part /     --ondisk=vda                                 --source rootfs            --fstype=ext4 --label root
```

meta-arm の wks は古い名前の `bootimg-partition` のまま。wic が古い名前も受け付けるのかは、6 章で確かめる。

U-Boot の標準ブート（bootstd）は `boot.scr` も `extlinux.conf` も探すので、どちらでも起動できる（aarch64-boot-lab の U-Boot 2024.01 も bootstd で `boot.scr` を見つけていた）。この章では aarch64-boot-lab と同じ `boot.scr` を使い、6 章で extlinux と比べる。

## 5. runqemu で U-Boot から起動する

`runqemu` は `QB_DEFAULT_BIOS` があれば `-bios` を付け、カーネルがあれば `-kernel` を付ける（`scripts/runqemu` の `check_bios()` と `start_qemu()`）。aarch64-boot-lab で分かったとおり、`-kernel` を渡すと U-Boot は fw_cfg 経由の起動を先に選んでしまうので、カーネルは渡さない。

カーネルを渡さない設定は `QB_DEFAULT_KERNEL = "none"`（`check_kernel()` は `none` なら何もしない）。meta-yocto-bsp の `genericarm64.conf` が同じ設定をしている（10 章）。

`local.conf`:

```
QB_DEFAULT_BIOS = "u-boot.bin"
QB_DEFAULT_KERNEL = "none"
QB_DEFAULT_FSTYPE = "wic"
QB_FSINFO = "wic:no-kernel-in-fs"
QB_ROOTFS_OPT = "-drive id=disk0,file=@ROOTFS@,if=none,format=raw -device virtio-blk-pci,drive=disk0"
```

- `QB_FSINFO = "wic:no-kernel-in-fs"` は名前に反して、カーネルを渡さない設定ではない。「wic の中にカーネルがない」という意味で、runqemu は wic を rootfs だけのイメージとして扱い、カーネルを探して `-kernel` を付けようとする。それを `QB_DEFAULT_KERNEL = "none"` で止める
- `QB_FSINFO` を書かない場合、runqemu は wic を「カーネル入りの VM イメージ」として扱い、`-kernel` を付けない。どちらの書き方がよいかは試して決める

<!-- TODO: runqemu が実行した QEMU のコマンドラインを logs/ に残し、-kernel が付いていないことを確かめる -->

```sh
bitbake core-image-minimal
runqemu qemuarm64 nographic slirp wic
```

## 6. 確かめること

aarch64-boot-lab の `logs/boot-uboot-rootdisk-6.18-*.log` と並べて比べる。

- U-Boot の版（`U-Boot 2026.01` と `U-Boot 2024.01`）
- `boot.scr` を読んだところ（aarch64-boot-lab では `** Booting bootflow 'virtio-blk#31.bootdev.part_1' with script`）
- カーネルのコマンドライン（`Kernel command line:`）
- `VFS: Mounted root (ext4 filesystem) on device 254:2.`
- 例外レベル（どちらも EL1 のはず）

<!-- TODO: 起動ログを logs/boot-yocto-uboot.log に保存して比べる -->
