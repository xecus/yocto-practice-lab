# 10 章: BSP を読む

11・12 章で Raspberry Pi 4 / 5 を動かす前に、BSP（Board Support Package）が何を決めているかを、4 つの MACHINE を並べて読む。

> **下書き**: 表の値は各レイヤーのソースから写した。genericarm64 の起動はまだ確かめていない。

## 1. 4 つの MACHINE

| | qemuarm64 | genericarm64 | raspberrypi4-64 | raspberrypi5 |
|---|---|---|---|---|
| レイヤー | openembedded-core | meta-yocto-bsp | meta-raspberrypi | meta-raspberrypi |
| tune | cortexa57 | armv8a-crc | cortexa72-nocrypto | cortexa76 |
| カーネル | linux-yocto 6.18.54 | linux-yocto 6.18.54 | linux-raspberrypi 6.18.33 | linux-raspberrypi 6.18.33 |
| デバイスツリー | QEMU が作る | ファームウェアが UEFI で渡す（QEMU では、U-Boot が QEMU の作った DTB を渡す） | `bcm2711-rpi-4-b.dtb` など | `bcm2712-rpi-5-b.dtb` など |
| ブートローダー | なし（`-kernel`） | U-Boot → UEFI → GRUB / systemd-boot | GPU のファームウェア（U-Boot は任意） | 同じ |
| EL3 | なし（QEMU） | なし（QEMU） | `armstub8-gic.bin` | ファームウェアに内蔵（未確認） |
| シリアル | `ttyAMA0` | `ttyAMA0` ほか多数 | `ttyS0` | `ttyAMA10` |
| イメージ | `ext4.zst` | `wic.zst` | `wic.bz2` + `wic.bmap` | 同じ |

確かめるコマンド:

```sh
bitbake -e core-image-minimal | grep -E '^(DEFAULTTUNE|PREFERRED_PROVIDER_virtual/kernel|KERNEL_IMAGETYPE|KERNEL_DEVICETREE|SERIAL_CONSOLES|IMAGE_FSTYPES|WKS_FILE)='
```

<!-- TODO: 4 つの MACHINE で上のコマンドを実行して、表を確かめる -->

## 2. BSP レイヤーとディストリビューションのレイヤーを分ける

| レイヤー | 置くもの | このリポジトリ |
|---|---|---|
| BSP | MACHINE、カーネル・ブートローダーの設定、デバイスツリー、ファームウェア | meta-raspberrypi、meta-yocto-bsp、`meta-practice-bsp`（自作） |
| ディストリビューション | DISTRO、init、パッケージの方針 | meta-poky、`meta-practice` |
| アプリ | レシピ | `meta-practice` |

分けておくと、ボードを変えても DISTRO とアプリはそのまま使える。11・12 章で、`meta-practice` を変えずに MACHINE だけ変えて確かめる。

`meta-practice-bsp` には、5〜8 章で QEMU の「架空のボード」の BSP をすでに入れてある（U-Boot のブートスクリプト、wks、TF-A の設定、CPU ごとの MACHINE）。

## 3. QEMU の BSP

QEMU 向けの BSP（qemuarm64）は openembedded-core に最初から入っている。実機の BSP と同じ部品があり、中身が QEMU 向けになっている。

| 部品 | Raspberry Pi 4 | qemuarm64 |
|---|---|---|
| MACHINE の設定 | `raspberrypi4-64.conf`（meta-raspberrypi） | `qemuarm64.conf` + `qemu.inc`（openembedded-core） |
| カーネル | linux-raspberrypi | linux-yocto（`KBRANCH:qemuarm64`、`COMPATIBLE_MACHINE`） |
| デバイスツリー | BSP が持つ（`bcm2711-rpi-4-b.dtb`） | **持たない**。QEMU が起動時に作る |
| ブートローダー | GPU のファームウェア + armstub | なし（`-kernel`）。U-Boot は任意 |
| 書き込み・起動 | SD カードに wic を書いて電源を入れる | **`QB_*` の変数** → `qemuboot.conf` → `runqemu` |

## 4. 自分の BSP にデバイスツリーとカーネルの設定を足す

`meta-practice-bsp` に、実機の BSP が持つものを足す。

```
meta-practice-bsp/
├── conf/machine/practice-virt.conf     QB_DTB で自分のデバイスツリーを渡す
├── recipes-kernel/linux/
│   ├── linux-yocto_%.bbappend          COMPATIBLE_MACHINE、KMACHINE
│   └── files/practice-virt.scc         linux-yocto の BSP の記述（設定の断片をまとめる）
└── recipes-bsp/device-tree/            aarch64-boot-lab の virt.dts に部品を 1 つ足したもの
```

<!-- TODO: QB_DTB で渡したデバイスツリーで起動できるか。足した部品が /proc/device-tree に見えるか -->

## 5. genericarm64 を QEMU で起動する

SystemReady 向けの汎用 BSP。1 つのイメージを、UEFI を持つ多くのボードで動かす考え方。

```sh
bitbake-config-build enable-fragment machine/genericarm64
bitbake core-image-minimal
runqemu nographic slirp    # MACHINE の名前は付けない（1 章の 5）
```

`genericarm64.conf` の QEMU の設定は、5 章で使うもの（U-Boot から起動し、`QB_DEFAULT_KERNEL = "none"` で `-kernel` を渡さない）と同じ。

```
QB_DEFAULT_BIOS ?= "u-boot.bin"
QB_DEFAULT_KERNEL ?= "none"
QB_FSINFO ?= "wic:no-kernel-in-fs"
```

<!-- TODO: 起動ログ。U-Boot → EFI → GRUB → カーネルの流れを、5 章の boot.scr と比べる。tune が armv8a-crc なのでユーザーランドはビルドし直しになる -->
