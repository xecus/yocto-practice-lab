# yocto-practice

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

Wrynose の公式の目安は「RAM 32GB、ディスク 140GB」（[System Requirements](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html)）。RAM が足りないので、並列数を 2 に下げてビルドしている（[1 章](docs/01-build-and-runqemu.md) を参照）。

## 章

| 章 | 内容 | aarch64-boot-lab で対応するもの |
|---|---|---|
| [1](docs/01-build-and-runqemu.md) | `bitbake-setup` で Poky を用意し、`core-image-minimal` をビルドして `runqemu` で起動する | `./run.sh direct`（QEMU → カーネル） |
| 2 | ビルドの中身を見る（`tmp/work`、タスク、`bitbake -e`、sstate） | 手でビルドした `linux-*/` `busybox/` |
| 3 | 自作レイヤーと `bbappend` の最小限 | `configs/` |
| 4 | カーネルのカスタマイズ（config fragment、パッチ、版の切り替え） | `linux-<版>/` と `.config` |
| 5 | U-Boot を入れる | `./run.sh uboot-rootdisk` |
| 6 | TF-A を入れる | `./run.sh tfa-uboot-rootdisk` |
| 7 | wic と initramfs | `make-bootdisk.sh` / `make-rootdisk.sh` |
| 8 | 独自の MACHINE / DISTRO | `select-cpu.sh` |
| 9 | デバッグ（gdb、ログ） | `debug-<版>.gdb`、`logs/` |

2 章以降はまだ書いていない。起動まわりができたら、レシピの書き方・パッケージ・ライセンス・SDK などに進む。

## ディレクトリ構成

```
.
├── README.md
├── docs/                 章ごとの説明
├── logs/                 実行ログ（git 管理外）
│
│  ── 以下はセットアップで用意する（git 管理外）──
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
