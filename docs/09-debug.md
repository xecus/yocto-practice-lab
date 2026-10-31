# 9 章: デバッグ

aarch64-boot-lab の `./run.sh direct-debug` と `debug-6.18.gdb` で、カーネルの入口から `/init` までを gdb で追った。同じことを Yocto でビルドしたカーネルでやる。あわせて、ユーザーランドのデバッグと、ビルドの失敗の調べ方も扱う。

> **下書き**: runqemu のオプションはソースで確かめた（runqemu に gdb 専用のオプションはない）。手順はまだ試していない。

## 1. カーネルを gdb で追う

### QEMU を止めた状態で起動する

`runqemu` に gdb 用のオプションはないので、`qemuparams` で `-s -S` を渡す。`nokaslr` は `bootparams` で渡す。

```sh
# 端末 1
runqemu qemuarm64 nographic slirp qemuparams="-s -S" bootparams="nokaslr"
```

- `-s`: TCP 1234 番で gdb を待つ
- `-S`: CPU を止めたまま始める
- `nokaslr`: aarch64-boot-lab と同じく、`vmlinux` のシンボルと実行時のアドレスを一致させる
- qemuarm64 は `-smp 4`。aarch64-boot-lab と同じく 1 CPU で追うなら `qemuparams="-s -S -smp 1"`

<!-- TODO: qemuparams の -smp が QB_SMP より優先されるか確かめる -->

### vmlinux

カーネルのビルドディレクトリにある。

```sh
bitbake -e virtual/kernel | grep '^B='
ls -l <B>/vmlinux
```

linux-yocto の qemuarm64 で `CONFIG_DEBUG_INFO` が有効かは 4 章で確かめる。無効なら config fragment で有効にする。

<!-- TODO: vmlinux の場所と、デバッグ情報があるか（file vmlinux / readelf -S） -->

### gdb スクリプト

aarch64-boot-lab の `debug-6.18.gdb` を元にする。6.18 なので、ブレークポイントの関数名（`do_populate_rootfs` など）はそのまま使えるはず。

```
# debug-yocto.gdb（案）
set architecture aarch64
file <B>/vmlinux
target remote :1234
hbreak *0x40200000          # カーネルの入口（物理アドレス）
hbreak __primary_switched
hbreak start_kernel
hbreak do_populate_rootfs
hbreak run_init_process
continue
```

<!-- TODO: カーネルの入口のアドレスを確かめる（aarch64-boot-lab の 6.18 は 0x40200000。QEMU の -kernel の置き方なので同じはず）。/init は initramfs がないので run_init_process ではなく、/sbin/init（sysvinit）になる -->

```sh
# 端末 2
gdb-multiarch -x debug-yocto.gdb
```

Yocto の SDK にも gdb（`aarch64-poky-linux-gdb`）が入る。ホストの `gdb-multiarch` と比べる。

## 2. ユーザーランドのプログラムを gdb で追う

### デバッグ情報をイメージに入れる

```
# local.conf
IMAGE_FEATURES += "tools-debug dbg-pkgs"
```

- `tools-debug`: ターゲットに gdb と gdbserver を入れる
- `dbg-pkgs`: すべてのパッケージの `-dbg`（デバッグ情報）を入れる。イメージが大きくなる

イメージに入れずに、別のファイルシステムにする方法もある。

```
IMAGE_GEN_DEBUGFS = "1"
IMAGE_FSTYPES_DEBUGFS = "tar.bz2"
```

`IMAGE_GEN_DEBUGFS` は「デバッグ情報とソースを入れた、対になるファイルシステムを作る」（`documentation.conf` の説明）。

### gdbserver で追う

```sh
# ゲスト
gdbserver :2345 /bin/busybox ls
# ホスト（slirp では、ゲストのポートをホストに転送する設定が必要）
```

<!-- TODO: slirp のポート転送（qemuparams か QB_SLIRP_OPT）を調べる。tap なら 192.168.7.2 に直接つなげる（tap は sudo が必要） -->

## 3. SDK

```sh
bitbake core-image-minimal -c populate_sdk
ls tmp/deploy/sdk/
```

できたインストーラーを実行すると、クロスコンパイラ・sysroot・gdb が入る。aarch64-boot-lab で使った Ubuntu の `aarch64-linux-gnu-gcc` の代わりに、イメージと同じライブラリでアプリをビルドできる。

<!-- TODO: SDK の大きさ、インストール先、hello world をビルドしてゲストで動かす -->

## 4. ビルドの失敗を調べる

| 調べたいこと | 見るところ・コマンド |
|---|---|
| タスクのログ | `tmp/work/<アーキ>/<レシピ>/<版>/temp/log.do_<タスク>` |
| タスクが実行したコマンド | 同じディレクトリの `run.do_<タスク>` |
| ビルド環境の中で手で試す | `bitbake -c devshell <レシピ>`（`CC` などが設定されたシェル） |
| 変数がどこで決まったか | `bitbake -e <レシピ>`（2・3 章） |
| どのパッケージにファイルが入ったか | `oe-pkgdata-util find-path /bin/busybox` |
| パッケージの中身 | `oe-pkgdata-util list-pkg-files busybox` |
| 全体の実行ログ | `tmp/log/cooker/qemuarm64/` |

<!-- TODO: 3 章の「わざと失敗させる」と組み合わせて、devshell で直すまでの流れを書く -->

## 5. 起動ログを残す

aarch64-boot-lab の `run.sh` は、起動ごとに `logs/boot-*.log` を残した。Yocto でも同じように残すスクリプト（`run.sh`）を作る。

```sh
runqemu qemuarm64 nographic slirp 2>&1 | tee logs/boot-yocto-direct.log
```

<!-- TODO: run.sh を作る。起動方法（direct / uboot / tfa）と MACHINE を引数で選べるようにする -->
