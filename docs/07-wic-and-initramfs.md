# 7 章: wic と initramfs

aarch64-boot-lab の `make-bootdisk.sh`（initramfs 用のディスク）と `make-rootdisk.sh`（p1: `boot.scr` とカーネル、p2: ext4 の rootfs）を、Yocto の wic とイメージの設定で置き換える。

> **下書き**: 変数名と wks のオプションはソースで確かめた。出力はまだ確かめていない。

## 1. イメージの形式（IMAGE_FSTYPES）

qemuarm64 の既定（`qemu.inc`）:

```
IMAGE_FSTYPES += "tar.zst ext4.zst"
```

| 形式 | 中身 | aarch64-boot-lab で対応するもの |
|---|---|---|
| `ext4` / `ext4.zst` | rootfs だけの ext4 | `make-rootdisk.sh` の p2（`mkfs.ext4 -d`） |
| `tar.zst` | rootfs の tar | — |
| `cpio.gz` | initramfs | `busybox/rootfs.img`（`cpio -H newc`） |
| `wic` | パーティションを切ったディスク全体 | `rootdisk-*.img` / `bootdisk-*.img` |
| `wic.qcow2` | wic を qcow2 にしたもの | — |

```sh
bitbake -e core-image-minimal | grep -E '^(IMAGE_FSTYPES|IMAGE_ROOTFS_SIZE|IMAGE_ROOTFS_EXTRA_SPACE|IMAGE_OVERHEAD_FACTOR)='
```

<!-- TODO: 出力。ext4 の大きさがどう決まるか -->

## 2. wks ファイル

wic は `.wks`（kickstart 形式）でディスクの構成を決める。openembedded-core の例は `meta/files/wic/` にある（`directdisk.wks`、`sdimage-bootpart.wks`、`qemuriscv.wks` など）。

5 章で作った `qemuarm64-uboot.wks` は、aarch64-boot-lab の `make-rootdisk.sh` に合わせてある（MBR、p1 は 1MiB の位置から 64MiB の ext4）。

<!-- TODO: できた wic と rootdisk-6.18.img のパーティション表（fdisk -l）を並べて比べる -->

| オプション | 意味 |
|---|---|
| `--source rootfs` | イメージの rootfs を入れる |
| `--source bootimg_partition` | `IMAGE_BOOT_FILES` のファイルを入れる |
| `--fstype` | `ext4` / `vfat` など |
| `--label` | ファイルシステムのラベル |
| `--align` | 先頭の位置を KB 単位でそろえる |
| `--size` | 大きさ（MB など）。`rootfs` なら省略できる |
| `--active` | MBR の起動フラグ |
| `bootloader --ptable gpt` | GPT にする（省略すると MBR） |

## 3. wic の中身を見る

Wrynose では、wic は openembedded-core の `scripts/` から外れて、独立したレシピ（`meta/recipes-support/wic/wic_0.3.1.bb`、ソースは `git.yoctoproject.org/wic.git`）になった。ビルドディレクトリで `wic` と打っても使えないので、`wic-native` として使う。

```sh
bitbake wic-native wic-tools
W=tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.rootfs.wic
oe-run-native wic-native wic ls $W                 # パーティションの一覧
oe-run-native wic-native wic ls $W:1               # p1 の中身
oe-run-native wic-native wic cp $W:1/boot.scr .    # 取り出す
```

aarch64-boot-lab では `fdisk -l` と `mount -o loop` で確かめていたことが、root 権限なしでできる。

<!-- TODO: oe-run-native で動くか確かめる。ext4 / vfat の中を読むための debugfs・mtools が wic-native の sysroot にあるか（wic-tools を先にビルドしている） -->

## 4. initramfs

aarch64-boot-lab の `direct` / `uboot-qfw` / `uboot-initrd-disk` は、BusyBox の `_install/` を cpio にした initramfs を使い、`/init` スクリプトでシェルを起動した。

Yocto の initramfs 用イメージ（`meta/recipes-core/images/`）:

| イメージ | 内容 |
|---|---|
| `core-image-minimal-initramfs` | 本当の rootfs を探して切り替えるための initramfs |
| `core-image-tiny-initramfs` | サイズを小さくした initramfs |
| `core-image-initramfs-boot` | initramfs から起動するための最小構成 |

### A. initramfs を別ファイルにして渡す

```sh
bitbake core-image-minimal-initramfs
runqemu nographic slirp ramfs core-image-minimal-initramfs    # MACHINE の名前は付けない（1 章の 5）
```

aarch64-boot-lab の `direct`（`-kernel Image -initrd rootfs.img`）に相当する。

<!-- TODO: runqemu の ramfs で -initrd が付くか、起動して何が動くか（/init が何か） -->

### B. カーネルに埋め込む

```
INITRAMFS_IMAGE = "core-image-minimal-initramfs"
INITRAMFS_IMAGE_BUNDLE = "1"
```

カーネルのビルドの中で initramfs を `Image` に埋め込む（`CONFIG_INITRAMFS_SOURCE`）。`qemuboot.bbclass` は、`INITRAMFS_IMAGE_BUNDLE = "1"` のとき `QB_DEFAULT_KERNEL` を `${KERNEL_IMAGETYPE}-${INITRAMFS_LINK_NAME}.bin` にする。

### C. aarch64-boot-lab と同じ「BusyBox だけの initramfs」を作る

自分のイメージレシピを書く。`/init` は aarch64-boot-lab の `boot/initramfs-init` を使う。

```
# meta-practice/recipes-core/images/practice-initramfs.bb（案）
IMAGE_FSTYPES = "cpio.gz"
PACKAGE_INSTALL = "busybox practice-initramfs-init"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
inherit core-image
```

<!-- TODO: practice-initramfs-init のレシピ（/init を入れるだけ）を書いて確かめる。サイズを aarch64-boot-lab の rootfs.img と比べる -->

## 5. 大きさを比べる

<!-- TODO: aarch64-boot-lab の rootfs.img / rootdisk-*.img と、Yocto の cpio.gz / ext4 / wic の大きさを表にする -->
