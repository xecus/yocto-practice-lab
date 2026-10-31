# 3 章: 自作レイヤーと bbappend の最小限

4 章以降でカーネル・U-Boot・TF-A を変えるときに使う、自作レイヤー `meta-practice` を作る。
既存のレシピに手を入れる `bbappend` と、変数の書き方（`:append` など）を、`bitbake -e` で確かめながら身につける。

aarch64-boot-lab の `configs/` に `.config` を保存して管理していたのに相当する。Yocto では、レシピは直接書き換えず、自分のレイヤーに差分を置く。

> **下書き**: 手順は bitbake / openembedded-core のドキュメントとソースから書いた。出力はまだ確かめていない。

## 1. レイヤーを作る

レイヤーはリポジトリのトップに置いて、git で管理する（`bitbake-builds/` は git 管理外なので、その中には置かない）。

```sh
cd bitbake-builds/poky-wrynose/build
. ./init-build-env
bitbake-layers create-layer ../../../meta-practice
bitbake-layers add-layer ../../../meta-practice
bitbake-layers show-layers
```

できるもの:

```
meta-practice/
├── conf/layer.conf
├── COPYING.MIT
├── README
└── recipes-example/example/example_0.1.bb
```

`conf/layer.conf` で見るところ:

| 変数 | 意味 |
|---|---|
| `BBFILES` | このレイヤーのどのファイルをレシピとして読むか（`recipes-*/*/*.bb` と `.bbappend`） |
| `BBFILE_PRIORITY_meta-practice` | 同じレシピが複数のレイヤーにあるとき、どちらを使うか |
| `LAYERDEPENDS_meta-practice` | 依存するレイヤー（`core`） |
| `LAYERSERIES_COMPAT_meta-practice` | 対応するリリース（`wrynose`）。合わないと警告やエラーになる |

<!-- TODO: 生成された layer.conf の中身、show-layers の出力 -->

`bblayers.conf` は `bitbake-builds/` の中にあって git 管理外なので、別の環境で同じ状態にするには `add-layer` をやり直す必要がある。手順は README に書いておく。

## 2. 最初のレシピを動かす

```sh
bitbake example
cat tmp/work/*/example/0.1/temp/log.do_compile
```

`example_0.1.bb` は何もしないレシピ。タスクの流れ（2 章）を自分のレシピで確かめる。使い終わったら消してよい。

## 3. 最初の bbappend: BusyBox にアプレットを足す

BusyBox のレシピは `.cfg`（設定の断片）を重ねて `.config` を作る（2 章を参照）。自分の `.cfg` を足して、アプレットを 1 つ増やす。

足すアプレットの例: `CONFIG_TREE`（`tree` コマンド）。core-image-minimal に入っていないことを先に確かめる。

```sh
grep CONFIG_TREE tmp/work/cortexa57-poky-linux/busybox/1.37.0/build/.config
```

ファイルを作る。

```
meta-practice/recipes-core/busybox/
├── busybox_%.bbappend
└── files/
    └── tree.cfg
```

`busybox_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://tree.cfg"
```

`files/tree.cfg`:

```
CONFIG_TREE=y
```

- `%` はバージョンの部分に何でも合う（`busybox_1.37.0.bb` に効く）
- `FILESEXTRAPATHS:prepend` で、`file://` を探すディレクトリに自分の `files/` を足す
- `:=` は「その場で展開する」。`${THISDIR}` をこの bbappend のあるディレクトリにするために必要

確かめる。

```sh
bitbake-layers show-appends busybox
bitbake busybox
grep CONFIG_TREE tmp/work/cortexa57-poky-linux/busybox/1.37.0/build/.config
bitbake core-image-minimal
runqemu qemuarm64 nographic slirp    # 起動して tree を実行する
```

<!-- TODO: show-appends の出力、.config の変化、起動して tree が動くこと -->

## 4. 変数の書き方を確かめる

`local.conf` か、自分のレシピに次を書いて、`bitbake -e` で値を見る。

| 書き方 | 意味 | いつ効くか |
|---|---|---|
| `A = "x"` | 代入 | すぐ |
| `A ?= "x"` | まだ値がなければ代入 | すぐ |
| `A ??= "x"` | ほかに代入がなければ使う（いちばん弱い既定値） | 全部読んだあと |
| `A := "${B}"` | その場で展開して代入 | すぐ |
| `A += "x"` / `A =+ "x"` | 空白を入れて後ろ / 前に足す | すぐ |
| `A:append = " x"` / `A:prepend = "x "` | 後ろ / 前に足す（空白は自分で入れる） | 全部読んだあと |
| `A:remove = "x"` | 空白で区切った要素 `x` を消す | 全部読んだあと |
| `A:qemuarm64 = "x"` | MACHINE が qemuarm64 のときだけ代入（OVERRIDES） | 全部読んだあと |

試す（`meta-practice/recipes-example/example/example_0.1.bb` の末尾に書く）:

```
TEST_A = "1"
TEST_A += "2"
TEST_A:append = " 3"
TEST_A = "4"           # += は上書きされるが、:append は残る
TEST_B ??= "weak"
TEST_B ?= "default"
TEST_C = "a b c"
TEST_C:remove = "b"
TEST_D = "generic"
TEST_D:qemuarm64 = "arm64"
```

```sh
bitbake -e example | grep -E '^TEST_[A-D]='
```

予想（確かめて直す）:

```
TEST_A="4 3"
TEST_B="default"
TEST_C="a  c"
TEST_D="arm64"
```

- `TEST_C` は空白が 2 つになる。`:remove` は空白も含めて分割し、消した要素だけを抜いて、残りをそのままつなぐ（`bitbake/lib/bb/data_smart.py`）

<!-- TODO: 実際の出力。予想と違えば理由を書く -->

`bitbake -e` の `#` の行で、どの操作がどの順に効いたかを見る。

```sh
bitbake -e example | grep -B 20 '^TEST_A=' | grep '^#'
```

## 5. わざと失敗させる

よくある失敗を再現して、どう見えるかを確かめておく。

| 失敗 | 再現のしかた | 見え方 |
|---|---|---|
| bbappend の対象がない | `busybox_1.36.bbappend` にする | `No recipes in default available for: ... busybox_1.36.bbappend` のようなエラー |
| `FILESEXTRAPATHS` を書き忘れる | 1 行目を消す | `do_fetch` で `tree.cfg` が見つからない |
| `:append` の空白を忘れる | `SRC_URI:append = "file://tree.cfg"` | 前の要素とつながって別の URL になる |
| `LAYERSERIES_COMPAT` が合わない | `scarthgap` にする | レイヤーが互換でないというエラー |

<!-- TODO: それぞれの実際のエラーメッセージ -->
