# 2 章: ビルドの中身を見る

1 章の `bitbake core-image-minimal` で何が起きたかを、ファイルとタスクで追う。
aarch64-boot-lab で `linux-6.18.53/` や `busybox/` の中で `make` したことが、Yocto ではどこで行われているかを確かめる。

> **下書き**: コマンドと見る場所はソース（openembedded-core / bitbake）を読んで決めた。出力はまだ確かめていない（`<!-- TODO -->` の箇所）。

以下は、ビルドディレクトリ（`bitbake-builds/poky-wrynose/build`）で `. ./init-build-env` してから作業する。

## 1. ビルドディレクトリの全体

```
build/
├── conf/
│   ├── local.conf          自分で書く設定（1 章で並列数を足した）
│   ├── toolcfg.conf        bitbake-config-build が書く（OE_FRAGMENTS）
│   ├── bblayers.conf       使うレイヤー
│   └── site.conf → ../../site.conf  DL_DIR・SSTATE_DIR
└── tmp/
    ├── work/               レシピごとの作業場所
    ├── deploy/
    │   ├── images/qemuarm64/   できたイメージ・カーネル
    │   ├── rpm/                パッケージ（Poky の既定は rpm）
    │   └── licenses/           ライセンス情報
    ├── sysroots-components/    レシピがほかのレシピに渡すヘッダー・ライブラリ
    ├── stamps/             タスクが終わった印
    └── log/cooker/         bitbake の実行ログ
```

<!-- TODO: du -sh tmp/* の結果 -->

## 2. 1 つのレシピの作業場所（BusyBox）

aarch64-boot-lab では `busybox/` に clone して `make defconfig` → `make` → `make install` した。Yocto では同じことが `tmp/work/` の中で行われる。

```sh
ls tmp/work/
ls tmp/work/cortexa57-poky-linux/busybox/1.37.0/
```

| ディレクトリ | 中身 | aarch64-boot-lab で対応するもの |
|---|---|---|
| `sources/` | 展開したソース（`S`）。パッチ適用後 | `busybox/`（git clone したもの） |
| `build/` | ビルドの出力（`B`）。BusyBox は `S` と同じ場所でビルドする | `busybox/` |
| `image/` | `do_install` の出力（`D`） | `busybox/_install/` |
| `packages-split/` | パッケージごとに分けたファイル | — |
| `temp/log.do_<タスク>` | タスクのログ | 端末に出た `make` の出力 |
| `temp/run.do_<タスク>` | タスクとして実際に実行したシェルスクリプト | 自分で打ったコマンド |
| `recipe-sysroot/` | このレシピのビルドに使うヘッダー・ライブラリ | — |
| `recipe-sysroot-native/` | このレシピのビルドに使うホスト用のツール（クロスコンパイラなど） | Ubuntu の `aarch64-linux-gnu-gcc` |

- アーキのディレクトリ名（`cortexa57-poky-linux`）は `TUNE_FEATURES` から決まる。MACHINE に依存するレシピ（カーネルなど）は `qemuarm64-poky-linux/` に入る
- どのディレクトリが何の変数かは `bitbake -e busybox | grep -E '^(S|B|D|WORKDIR|UNPACKDIR)='` で確かめる

<!-- TODO: 実際のディレクトリ名と、bitbake -e の出力 -->

### `run.do_compile` を読む

```sh
less tmp/work/cortexa57-poky-linux/busybox/1.37.0/temp/run.do_compile
```

`do_compile` で実際に実行したシェルスクリプト。`CC=` や `CROSS_COMPILE=` の値を、aarch64-boot-lab で打った `make CROSS_COMPILE=aarch64-linux-gnu-` と比べる。

<!-- TODO: CC の値と、--sysroot が付いていること -->

## 3. タスク

```sh
bitbake -c listtasks busybox
```

レシピは決まった順にタスクを実行する。

```
do_fetch → do_unpack → do_patch → do_configure → do_compile → do_install
  → do_package → do_package_write_rpm → (イメージ側) do_rootfs → do_image
```

| タスク | やること | aarch64-boot-lab で対応するもの |
|---|---|---|
| `do_fetch` | ソースを `DL_DIR` に取得する | `git clone` / `wget` |
| `do_unpack` | `WORKDIR` に展開する | `tar xf` |
| `do_patch` | パッチを当てる | — |
| `do_configure` | 設定（BusyBox は `defconfig` と `.cfg` から `.config` を作る） | `make defconfig` + `make menuconfig` |
| `do_compile` | ビルド | `make` |
| `do_install` | `D` にインストール | `make install` |
| `do_package` | ファイルをパッケージに分ける | — |
| `do_rootfs` | パッケージを入れてルートファイルシステムを作る | `_install/` に手で足したもの |
| `do_image_*` | ext4 などのイメージにする | `make-rootdisk.sh`（`mkfs.ext4 -d`） |

1 つのタスクだけを実行し直す。

```sh
bitbake -c compile -f busybox    # -f: 終わっていても実行し直す
bitbake busybox                  # 続きのタスクも実行
```

<!-- TODO: listtasks の出力 -->

## 4. 変数の値と、それがどこで決まったか

```sh
bitbake -e busybox > busybox.env
grep -n '^SRC_URI=' busybox.env
```

`bitbake -e` は変数の最終的な値だけでなく、どのファイルのどの操作で値が変わったかも出す（`#` で始まる行）。

```sh
grep -B 30 '^SRC_URI=' busybox.env | grep '^#'
```

<!-- TODO: SRC_URI の履歴の例。busybox_1.37.0.bb と busybox.inc のどちらで設定されたか -->

## 5. BusyBox の設定を aarch64-boot-lab と比べる

aarch64-boot-lab は `defconfig` に `CONFIG_STATIC=y`・`tc` 無効を足した。Yocto の BusyBox は、レシピの `defconfig` に `.cfg`（`init.cfg`、`getopts.cfg` など）を重ねて作る。

```sh
B=tmp/work/cortexa57-poky-linux/busybox/1.37.0/build
diff <(grep '^CONFIG_' ~/aarch64-boot-lab/configs/busybox-1.32.config | sort) \
     <(grep '^CONFIG_' $B/.config | sort) | head -50
```

見るところ:
- `CONFIG_STATIC`: Yocto は glibc に動的リンクする（ライブラリはイメージに入っている）
- `CONFIG_INIT`: Poky の既定は sysvinit なので、BusyBox の init は使わない（`INIT_MANAGER = "sysvinit"`）

<!-- TODO: diff の結果と、目立つ違い -->

## 6. イメージに何が入ったか

```sh
ls -l tmp/deploy/images/qemuarm64/
cat tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.rootfs.manifest
```

- `*.manifest`: イメージに入ったパッケージの一覧
- `*.qemuboot.conf`: `runqemu` が読む設定（1 章で使った）
- `Image`: カーネル（aarch64-boot-lab の `arch/arm64/boot/Image` と同じ形式）

<!-- TODO: パッケージの数、ext4 の大きさ、Image の大きさ -->

## 7. sstate の効果を測る

`tmp/` を消して、もう一度ビルドする。ビルドの結果は `SSTATE_DIR`（`bitbake-builds/.sstate-cache/`）にキャッシュされているので、コンパイルせずに取り出すだけになる。

```sh
rm -rf tmp
time bitbake core-image-minimal
```

最初に表示される `Sstate summary` を、1 章のとき（`Wanted 2287 Local 0 ... Missed 2287`）と比べる。

<!-- TODO: 2 回目の Sstate summary と時間。1 章のビルド時間と比べる -->

- `DL_DIR` と `SSTATE_DIR` は `site.conf` で `bitbake-builds/` の下にあるので、ほかの setup directory（ほかのリリースなど）と共有される
- `tmp/` は消してよい。`DL_DIR` と `SSTATE_DIR` を消すと、次は最初からダウンロード・ビルドし直しになる

## 8. 依存関係を見る

```sh
bitbake -g core-image-minimal
ls *.dot task-depends.dot pn-buildlist
```

- `pn-buildlist`: ビルドしたレシピの一覧
- `task-depends.dot`: タスクの依存関係（大きいので、`grep` で必要なところだけ見る）

```sh
grep '"busybox.do_compile" ->' task-depends.dot
```

<!-- TODO: pn-buildlist の行数、busybox.do_compile が何に依存しているか -->
