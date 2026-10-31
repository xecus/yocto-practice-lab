# 11 章: Raspberry Pi 4

meta-raspberrypi で Raspberry Pi 4 向けのイメージを作り、UART のシリアルコンソールで起動ログを取る。直接起動 → U-Boot → TF-A の順に、boot-lab の起動方法と対応させる。

> **下書き**: 設定は meta-raspberrypi（wrynose、9195883、2026-10-10）のソースと docs から書いた。SD カードがまだないので、書き込みと起動は未確認。

## 準備するもの

| もの | 用途 |
|---|---|
| Raspberry Pi 4 | メモリの量は起動後に `/proc/meminfo` で確かめる（同じイメージで動く） |
| microSD カード | イメージを書き込む（**未入手**） |
| 3.3V の USB-UART アダプター | GPIO14（TXD）・GPIO15（RXD）・GND につなぐ。5V のアダプターは使わない |
| 電源 | 5V 3A（USB-C） |

## 1. meta-raspberrypi を追加してビルドする

```sh
cd bitbake-builds/poky-wrynose/layers
git clone -b wrynose https://git.yoctoproject.org/meta-raspberrypi
cd ../build
bitbake-layers add-layer ../layers/meta-raspberrypi
bitbake-config-build enable-fragment machine/raspberrypi4-64
```

`local.conf`:

```
ENABLE_UART = "1"
```

- MACHINE が推奨パッケージとして Wi-Fi のファームウェア（`linux-firmware-rpidistro-bcm43455` など）を入れようとする。このレシピは `LICENSE_FLAGS = "synaptics-killswitch"` なので、`LICENSE_FLAGS_ACCEPTED = "synaptics-killswitch"` がないと入らない（meta-raspberrypi の `docs/ipcompliance.md`）。ライセンスを読んでから決める

<!-- TODO: LICENSE_FLAGS_ACCEPTED なしでビルドしたとき、警告で済むか、エラーになるか -->

```sh
bitbake core-image-minimal
ls tmp/deploy/images/raspberrypi4-64/
```

- tune が `cortexa72-nocrypto` に変わるので、ユーザーランドはすべてビルドし直しになる（8 章で同じ tune の MACHINE を作っていれば、それを使い回せるかもしれない）

<!-- TODO: ビルド時間、Sstate summary、できたファイル -->

## 2. イメージの中身を見る（SD カードなしでできる）

wic は 7 章と同じく `oe-run-native wic-native` で使う。

```sh
W=tmp/deploy/images/raspberrypi4-64/core-image-minimal-raspberrypi4-64.rootfs.wic.bz2
bunzip2 -k $W
oe-run-native wic-native wic ls ${W%.bz2}
oe-run-native wic-native wic ls ${W%.bz2}:1
oe-run-native wic-native wic cp ${W%.bz2}:1/config.txt .
oe-run-native wic-native wic cp ${W%.bz2}:1/cmdline.txt .
```

p1（FAT）に入っているはずのもの:

| ファイル | 役割 | boot-lab で対応するもの |
|---|---|---|
| `start4.elf`、`fixup4.dat` | GPU のファームウェア（ARM より先に動く） | — |
| `armstub8-gic.bin` | EL3 で動き、EL2 に落としてカーネルに渡す | TF-A の BL31（ずっと小さい） |
| `kernel8.img` | カーネル | `Image` |
| `bcm2711-rpi-4-b.dtb`、`overlays/` | デバイスツリー | QEMU が作る DTB |
| `config.txt` | ファームウェアの設定（`enable_uart=1` など） | `run.sh` の QEMU のオプション |
| `cmdline.txt` | カーネルのコマンドライン | `-append` / `bootargs` |

<!-- TODO: 実際のファイル一覧、config.txt と cmdline.txt の中身 -->

## 3. SD カードに書き込んで起動する

```sh
sudo apt-get install bmap-tools picocom
sudo bmaptool copy $W /dev/sdX      # sdX は lsblk で確かめる。.wic.bmap を自動で使う
sudo picocom -b 115200 /dev/ttyUSB0
```

- `bmaptool` は `.wic.bmap` に書かれた、データのあるブロックだけを書き込むので、`dd` より速い
- 書き込み先を間違えるとホストのディスクを壊す。`lsblk` で、SD カードを挿す前と後を比べて決める

<!-- TODO: 起動ログを logs/boot-rpi4-direct.log に保存。Booting Linux on physical CPU の MIDR と CPU features を、boot-lab の --cpu a72 と比べる。EL（armstub は EL2 で渡すはず） -->

## 4. U-Boot を通す

```
RPI_USE_U_BOOT = "1"
```

`UBOOT_MACHINE = "rpi_arm64_config"`。U-Boot の動作には `enable_uart=1` が必要（meta-raspberrypi の docs/extra-build-config.md）。

<!-- TODO: 起動ログを boot-lab の uboot-rootdisk と比べる。boot.scr は rpi-u-boot-scr レシピが作る -->

## 5. armstub を TF-A に置き換える

TF-A には Raspberry Pi 4 向けのプラットフォーム（`PLAT=rpi4`）がある。BL31 を作り、`config.txt` の `armstub=` で armstub8-gic.bin の代わりに読ませる。meta-arm の `trusted-firmware-a` レシピで `TFA_PLATFORM = "rpi4"` にする。

<!-- TODO: meta-arm の TF-A 2.14 で PLAT=rpi4 がビルドできるか。PSCI の応答者が変わることを、boot-lab の 6 章と同じく poweroff 時の表示で確かめる -->

## 6. カーネルの版を切り替える

linux-raspberrypi には 6.18 / 6.12 / 6.6 / 6.1 のレシピがある。qemuarm64 ではできなかった版の比較をする。

```
PREFERRED_VERSION_linux-raspberrypi = "6.6.%"
```

<!-- TODO: 6.18 / 6.12 / 6.6 で CPU features と起動時間を比べる。boot-lab の 5.4 / 6.18 / 7.2 の比較と並べる -->
