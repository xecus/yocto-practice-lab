# 12 章: Raspberry Pi 5

11 章と同じ流れを Raspberry Pi 5 でやり、Pi 4 と違うところを中心に見る。

> **下書き**: 設定は meta-raspberrypi（wrynose、9195883、2026-10-10）のソースから書いた。SD カードがまだないので、書き込みと起動は未確認。

## Pi 4 との違い

| | Raspberry Pi 4 | Raspberry Pi 5 |
|---|---|---|
| MACHINE | `raspberrypi4-64` | `raspberrypi5` |
| SoC / CPU | BCM2711 / Cortex-A72 | BCM2712 / Cortex-A76 |
| tune | `cortexa72-nocrypto` | `cortexa76` |
| カーネルのファイル名 | `kernel8.img` | `kernel_2712.img` |
| EL3 | `armstub8-gic.bin`（`ARMSTUB` で指定） | `ARMSTUB` の指定なし |
| シリアル（`SERIAL_CONSOLES`） | `ttyS0`（GPIO14/15） | `ttyAMA10`（専用の 3 ピンのデバッグ UART 端子） |
| U-Boot | `rpi_arm64_config` | `rpi_arm64_config`。`CONFIG_BOOTDELAY=-2` にしている（UART がつながっていないと止まる問題への対策） |
| 周辺機器 | SoC に直接つながる | 多くが PCIe の先の RP1 チップにつながる |

## 準備するもの

| もの | 用途 |
|---|---|
| Raspberry Pi 5 | |
| microSD カード | **未入手** |
| 3.3V の USB-UART アダプター | GPIO14・GPIO15・GND につなぐ（専用の 3 ピン端子は使わない） |
| 電源 | 5V 5A（USB-C、27W） |

### UART の注意

meta-raspberrypi の Pi 5 の既定は `ttyAMA10`（専用の 3 ピン端子）。GPIO14/15 の UART を使うので、コンソールを変える必要がある。

<!-- TODO: GPIO14/15 の UART が Linux から何という名前で見えるか（ttyAMA0 と思われる）、config.txt に何が必要か（enable_uart=1 だけで足りるか、dtparam=uart0 も要るか）を確かめて、SERIAL_CONSOLES と cmdline.txt の console= を直す -->

## 1. ビルド

```sh
bitbake-config-build enable-fragment machine/raspberrypi5
bitbake core-image-minimal
```

- tune が `cortexa76` に変わるので、ユーザーランドはすべてビルドし直し
- 8 章で `cortexa76` の MACHINE を作っていれば、それを使い回せるかもしれない

<!-- TODO: ビルド時間、Sstate summary -->

## 2. イメージの中身を見る

11 章と同じく `wic ls` で p1 を見る。Pi 4 との違いを確かめる。

<!-- TODO: start4.elf がないこと（Pi 5 のファームウェアは EEPROM に入っている）、armstub がないこと、kernel_2712.img、bcm2712-rpi-5-b.dtb -->

## 3. 起動

<!-- TODO: 起動ログを logs/boot-rpi5-direct.log に保存。MIDR と CPU features を、boot-lab の --cpu a76 と比べる。EL3 で何が動いているか（ファームウェアに TF-A の BL31 が入っていると思われる）を起動ログで確かめる -->

## 4. U-Boot と TF-A

11 章と同じ実験をする。TF-A には Raspberry Pi 5 向けのプラットフォーム（`PLAT=rpi5`）がある。

<!-- TODO: meta-arm の TF-A 2.14 で PLAT=rpi5 があるか。ファームウェア内蔵の BL31 を自分でビルドした BL31 に置き換えられるか -->
