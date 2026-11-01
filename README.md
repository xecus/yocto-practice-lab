# yocto-practice-lab

Yocto Project（Wrynose 6.0 LTS）で QEMU の aarch64 マシン `qemuarm64` 向けのイメージを作り、組み込み Linux の作り方を章ごとに試す実験環境。

[aarch64-boot-lab](https://github.com/xecus/aarch64-boot-lab) では、TF-A・U-Boot・Linux・BusyBox を手でビルドして起動の流れを追った。ここでは同じことを Yocto でやり、手でやった作業が Yocto のどこに対応するかを確かめる。

- Yocto: Wrynose 6.0 LTS（Poky 6.0.4、BitBake 2.18.0）
- MACHINE: `qemuarm64`（`TUNE_FEATURES = "aarch64 crc cortexa57"`）
- カーネル: linux-yocto 6.18（aarch64-boot-lab の `linux-6.18.53` と比べられる）
- init: sysvinit、C ライブラリ: glibc

## 動作確認した環境

| 項目 | バージョン・値 |
|---|---|
| ホスト | Ubuntu 24.04.5 LTS (x86_64) |
| CPU / RAM | 4 コア / 7GB（スワップ 4GB） |
| 空きディスク | 150GB |
| bitbake-setup | 2.19.0（pip） |

Wrynose の公式の目安は「RAM 32GB、ディスク 140GB」（[System Requirements](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html)）。RAM が足りないので、並列数を 2 に下げてビルドしている。この条件で、最初の `core-image-minimal` のビルドに 8 時間 12 分、ディスクを 73GB 使った（[1 章](docs/01-build-and-runqemu.md) を参照）。

## 章

| 章 | 内容 | aarch64-boot-lab で対応するもの |
|---|---|---|
| [1](docs/01-build-and-runqemu.md) | `bitbake-setup` で Poky を用意し、`core-image-minimal` をビルドして `runqemu` で起動する | `./run.sh direct`（QEMU → カーネル） |
| [2](docs/02-inside-the-build.md) | ビルドの中身を見る（`tmp/work`、タスク、`bitbake -e`、sstate） | 手でビルドした `linux-*/` `busybox/` |
| [3](docs/03-layer-and-bbappend.md) | 自作レイヤーと `bbappend` の最小限 | `configs/` |
| [4](docs/04-kernel.md) | カーネルのカスタマイズ（config fragment、パッチ、版の切り替え） | `linux-<版>/` と `.config` |
| [5](docs/05-u-boot.md) | U-Boot を入れる | `./run.sh uboot-rootdisk` |
| [6](docs/06-tf-a.md) | TF-A を入れる | `./run.sh tfa-uboot-rootdisk` |
| [7](docs/07-wic-and-initramfs.md) | wic と initramfs | `make-bootdisk.sh` / `make-rootdisk.sh` |
| [8](docs/08-machine-and-distro.md) | 独自の MACHINE / DISTRO | `select-cpu.sh` |
| [9](docs/09-debug.md) | デバッグ（gdb、ログ） | `debug-<版>.gdb`、`logs/` |
| [10](docs/10-bsp.md) | BSP を読む（qemuarm64・genericarm64・Raspberry Pi 4 / 5 の比較） | — |
| [11](docs/11-raspberrypi4.md) | Raspberry Pi 4（meta-raspberrypi、UART、U-Boot、TF-A、カーネルの版の切り替え） | `--cpu a72`、`tfa-uboot-rootdisk` |
| [12](docs/12-raspberrypi5.md) | Raspberry Pi 5（Pi 4 との違い） | `--cpu a76` |

1 章は実際に動かして確かめた。2 章以降は下書き（手順はソースを読んで書き、出力はまだ確かめていない）。1 章から順に確かめて書き直す。起動まわりができたら、レシピの書き方・パッケージ・ライセンス・SDK などに進む。

## 使い方

```sh
./setup.sh                    # 環境を作る（何度実行してもよい）
./build.sh                    # core-image-minimal をビルド（ログは logs/build-*.log）
./run.sh direct               # runqemu で起動（ログは logs/boot-*.log）。終了はゲストで poweroff
./run.sh --cpu a72 --smp 1 direct
. ./env.sh                    # 手で bitbake を打つとき（venv とビルド環境を読み込む）
```

`./run.sh -h`、`./build.sh -h` でオプションの一覧を表示する。

設定は `local.conf` を手で書き換えず、レイヤーの `conf/fragments/` にフラグメントとして置き、`bitbake-config-build enable-fragment practice/<名前>`（`meta-practice-bsp` なら `practice-bsp/<名前>`）で有効にする。

自作レイヤーは 2 つに分けている。ボードに依存しないもの（DISTRO、イメージ、アプリ）は `meta-practice`、ボードに関するもの（MACHINE、ブートローダー、デバイスツリー）は `meta-practice-bsp`。

## ディレクトリ構成

```
.
├── setup.sh              環境を作る（ホストの確認、bitbake-setup init、自作レイヤーの追加）
├── build.sh              ビルドする（MACHINE を -m で選ぶ）
├── run.sh                runqemu で起動する（起動方法・イメージ・MACHINE・CPU・CPU 数を選ぶ）
├── env.sh                source して使う（venv と init-build-env）
├── meta-practice/        自作レイヤー: ボードに依存しないもの（レイヤー名 practice）
│   └── conf/
│       ├── layer.conf
│       └── fragments/        practice/<名前> として有効にする設定
├── meta-practice-bsp/    自作レイヤー: ボードに関するもの（レイヤー名 practice-bsp）
│   └── conf/
│       ├── layer.conf
│       └── fragments/        practice-bsp/<名前> として有効にする設定
├── experiments/          章ごとの実験（準備 → 実行 → 結果を logs/ に保存 → 元に戻す）
├── docs/                 章ごとの説明
├── logs/                 実行ログ（git 管理外）
│
│  ── 以下は setup.sh が用意する（git 管理外）──
├── bitbake-setup-venv/   bitbake-setup を入れた Python の venv
└── bitbake-builds/       bitbake-setup の top directory
    ├── site.conf             DL_DIR・SSTATE_DIR（すべての setup で共有）
    ├── .bitbake-setup-downloads/   DL_DIR（ソースのダウンロード先）
    ├── .sstate-cache/              SSTATE_DIR（ビルド結果のキャッシュ）
    └── poky-wrynose/         setup directory
        ├── config/               bitbake-setup の設定（config-upstream.json）
        ├── layers/               bitbake・openembedded-core・meta-yocto など
        └── build/                ビルドディレクトリ（conf/、tmp/）
```

## ライセンス

このリポジトリのスクリプトと設定ファイルは [MIT License](LICENSE)。
セットアップで取得する BitBake・OpenEmbedded-Core・meta-yocto などは含まれておらず、それぞれのライセンスに従う。

## 注意

このリポジトリは個人の学習用で、Yocto Project・OpenEmbedded・Arm・Raspberry Pi の公式のプロジェクトではない。
Yocto Project は Linux Foundation の商標。
