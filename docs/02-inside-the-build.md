# 2 章: ビルドの中身を見る

1 章の `bitbake core-image-minimal` で何が起きたかを、ファイルとタスクで追う。
aarch64-boot-lab で `linux-6.18.53/` や `busybox/` の中で `make` したことが、Yocto ではどこで行われているかを確かめる。

以下は、ビルドディレクトリ（`bitbake-builds/poky-wrynose/build`）で作業する。リポジトリのトップで `. ./env.sh` すると、venv を有効にし、ビルドディレクトリに入って `init-build-env` を読む。

## 1. ビルドディレクトリの全体

```
build/
├── conf/
│   ├── local.conf          自分で書く設定（このリポジトリでは何も書かない）
│   ├── toolcfg.conf        bitbake-config-build が書く（OE_FRAGMENTS）
│   ├── bblayers.conf       使うレイヤー
│   └── site.conf → ../../../site.conf  DL_DIR・SSTATE_DIR
└── tmp/
    ├── work/               レシピごとの作業場所
    ├── work-shared/        複数のレシピで共有するソース（カーネル、gcc）
    ├── deploy/
    │   ├── images/qemuarm64/   できたイメージ・カーネル
    │   ├── rpm/                パッケージ（Poky の既定は rpm）
    │   ├── licenses/           ライセンス情報
    │   └── spdx/               SBOM
    ├── sysroots-components/    レシピがほかのレシピに渡すヘッダー・ライブラリ
    ├── pkgdata/            パッケージの中身の一覧（oe-pkgdata-util が読む）
    ├── stamps/             タスクが終わった印
    ├── buildstats/         タスクごとの時間・CPU・I/O
    ├── hosttools/          ビルドで使ってよいホストのコマンド（HOSTTOOLS）へのリンク
    └── log/cooker/         bitbake の実行ログ
```

1 章のビルドのあとの `du -sh tmp/*`（大きいものだけ）:

| ディレクトリ | 大きさ |
|---|---|
| `work/` | 50GB |
| `work-shared/` | 5.2GB |
| `sysroots-components/` | 3.9GB |
| `deploy/` | 2.2GB |
| `cache/` | 248MB |
| `log/` | 146MB |
| `sysroots-uninative/` | 117MB |
| `pkgdata/` | 56MB |
| `stamps/` | 51MB |
| `buildstats/` | 40MB |

- ほとんどは `work/`。レシピごとに、ソース・ビルドの途中のファイル・インストールしたもの・パッケージが全部残っている
- `hosttools/` には、ホストの `gcc` や `tar` などへのシンボリックリンクがある。BitBake のタスクの `PATH` には、ここと Yocto がビルドしたツールしか入らない。1 章で `chrpath diffstat gawk` が足りないと言われたのは、ここにリンクを作れなかったから

## 2. 1 つのレシピの作業場所（BusyBox）

aarch64-boot-lab では `busybox/` に clone して `make defconfig` → `make` → `make install` した。Yocto では同じことが `tmp/work/` の中で行われる。

```sh
ls tmp/work/
ls tmp/work/cortexa57-poky-linux/busybox/1.37.0/
```

作業場所（`WORKDIR`）は `tmp/work/<アーキ>/<レシピ名>/<版>/`。`bitbake.conf` の定義:

```
WORKDIR = "${BASE_WORKDIR}/${MULTIMACH_TARGET_SYS}/${PN}/${PV}"
UNPACKDIR ??= "${WORKDIR}/sources"
S = "${UNPACKDIR}/${BP}"
B = "${S}"
```

| ディレクトリ | 中身 | aarch64-boot-lab で対応するもの |
|---|---|---|
| `sources/` | `do_unpack` の展開先（`UNPACKDIR`）。`SRC_URI` の `file://` もここに入る | — |
| `sources/busybox-1.37.0/` | ソース（`S`）。パッチ適用後。BusyBox はここでビルドする（`B = S`）ので、`.config` もここにできる | `busybox/`（git clone したもの） |
| `image/` | `do_install` の出力（`D`） | `busybox/_install/` |
| `packages-split/` | パッケージごとに分けたファイル | — |
| `temp/log.do_<タスク>` | タスクのログ | 端末に出た `make` の出力 |
| `temp/run.do_<タスク>` | タスクとして実際に実行したシェルスクリプト | 自分で打ったコマンド |
| `recipe-sysroot/` | このレシピのビルドに使うヘッダー・ライブラリ | — |
| `recipe-sysroot-native/` | このレシピのビルドに使うホスト用のツール（クロスコンパイラなど） | Ubuntu の `aarch64-linux-gnu-gcc` |

- アーキのディレクトリ名（`cortexa57-poky-linux`）は `TUNE_FEATURES` から決まる。MACHINE に依存するレシピ（カーネル、`core-image-minimal`、`base-files` など）は `qemuarm64-poky-linux/` に入る
- `tmp/work/` にはほかに、`x86_64-linux/`（ホスト向けの `-native`）と `all-poky-linux/`（アーキに依存しないもの）がある

どのディレクトリが何の変数かを `bitbake -e` で確かめる（`build/tmp/work/cortexa57-poky-linux/busybox/1.37.0` を `<W>` と略した）。

```
$ bitbake -e busybox | grep -E '^(PN|PV|PR|BP|MULTIMACH_TARGET_SYS|WORKDIR|UNPACKDIR|S|B|D|STAGING_DIR_HOST|STAGING_DIR_NATIVE)='
BP="busybox-1.37.0"
MULTIMACH_TARGET_SYS="cortexa57-poky-linux"
PN="busybox"
PR="r0"
PV="1.37.0"
WORKDIR="<W>"
UNPACKDIR="<W>/sources"
S="<W>/sources/busybox-1.37.0"
B="<W>/sources/busybox-1.37.0"
D="<W>/image"
STAGING_DIR_HOST="<W>/recipe-sysroot"
STAGING_DIR_NATIVE="<W>/recipe-sysroot-native"
```

- `PR`（`r0`）はディレクトリ名に入らない
- `sources/` には、tarball を展開した `busybox-1.37.0/` と並んで、`SRC_URI` の `file://` のファイル（パッチ 29 個、`defconfig`、`.cfg`、起動スクリプトなど）がそのまま置かれる
- `image/bin/` には `busybox.nosuid`（3.6MB）と `busybox.suid`（457KB）がある。Yocto は BusyBox を**2 つ**に分けてビルドする（`login`・`su`・`passwd`・`ping` など setuid が必要な 7 個と、それ以外の 181 個）。`bin/busybox` と `bin/sh` は `busybox.nosuid` へのリンク
- `packages-split/` には `busybox`・`busybox-dbg`・`busybox-syslog`・`busybox-udhcpc` など 15 個。`packages-split/busybox/bin/busybox.nosuid` はデバッグ情報を外して 658KB になる

### `run.do_compile` を読む

```sh
less tmp/work/cortexa57-poky-linux/busybox/1.37.0/temp/run.do_compile
```

`do_compile` で実際に実行したシェルスクリプト（253 行）。前半で環境変数を `export` し、後半にレシピの `do_compile()` と、そこから呼ぶ関数（`oe_runmake` など）が入っている。どの関数がどのファイルから来たかは `# line: 48, file: .../base.bbclass` のようなコメントで分かる。

`oe_runmake` が実際に実行する `make`（`<W>` は上と同じ。`HOSTCC` は省いた）:

```
make -j 2 \
  CC='aarch64-poky-linux-gcc -mcpu=cortex-a57+crc -mbranch-protection=standard -fstack-protector-strong -O2 -D_FORTIFY_SOURCE=2 --sysroot=<W>/recipe-sysroot' \
  LD='aarch64-poky-linux-gcc ...（CC と同じ）' \
  V=1 ARCH=aarch64 CROSS_COMPILE=aarch64-poky-linux- SKIP_STRIP=y \
  HOSTCC='gcc ...' HOSTCPP='gcc -E' \
  busybox_unstripped
```

aarch64-boot-lab の `make CROSS_COMPILE=aarch64-linux-gnu-` と比べる。

| | aarch64-boot-lab | Yocto |
|---|---|---|
| コンパイラ | Ubuntu の `aarch64-linux-gnu-gcc` 13.3.0 | `<W>/recipe-sysroot-native/usr/bin/aarch64-poky-linux/aarch64-poky-linux-gcc` 15.3.0（Yocto がビルドした `gcc-cross-aarch64`） |
| `-j` | 自分で決める | `PARALLEL_MAKE`（`practice/lowmem` で 2） |
| CPU の指定 | なし | `-mcpu=cortex-a57+crc`（`TUNE_FEATURES` から） |
| ヘッダー・ライブラリ | Ubuntu のクロス用の glibc | `--sysroot=<W>/recipe-sysroot`。このレシピが `DEPENDS` に書いたものだけが入る |
| リンク | 静的（`CONFIG_STATIC=y`） | 動的。`file` で見ると `dynamically linked, interpreter /lib/ld-linux-aarch64.so.1` |
| セキュリティ | なし | `-fstack-protector-strong`、`-D_FORTIFY_SOURCE=2`、`-mbranch-protection=standard`（BTI と PAC） |

- `-mbranch-protection=standard` は Armv8.3 の PAC と Armv8.5 の BTI の命令を入れるが、それより古い CPU（A57 など）では何もしない命令（NOP）として動く
- `recipe-sysroot/` と `recipe-sysroot-native/` は、`do_prepare_recipe_sysroot` で `sysroots-components/` から、このレシピに必要なものだけをハードリンクして作る。`DEPENDS` に書き忘れたライブラリは見えないので、「自分の PC にはあったから通った」が起きない

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
| `do_unpack` | `UNPACKDIR`（`WORKDIR/sources`）に展開する | `tar xf` |
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

`bitbake -c listtasks busybox` の出力（説明は省いた）:

```
do_build                    do_fetch                    do_package_write_rpm
do_checkuri                 do_install                  do_packagedata
do_clean                    do_install_ptest_base       do_patch
do_cleanall                 do_listtasks                do_populate_lic
do_cleansstate              do_menuconfig               do_populate_sysroot
do_compile                  do_package                  do_prepare_recipe_sysroot
do_compile_ptest_base       do_package_qa               do_pydevshell
do_configure                do_recipe_qa                do_savedefconfig
do_configure_ptest_base     do_create_spdx など（SBOM）  do_showconfig
do_deploy_source_date_epoch do_devshell                 do_unpack
do_diffconfig
```

- 表にないタスク: `do_populate_sysroot`（ほかのレシピに渡すファイルを `sysroots-components/` に置く）、`do_packagedata`、`do_package_qa`（パッケージの検査）、`do_create_spdx`（SBOM）
- `*_ptest_base`: パッケージに付いているテストを、ターゲットで実行できる形にする。Poky の `DISTRO_FEATURES` に `ptest` があるので有効
- `do_menuconfig`・`do_diffconfig`・`do_savedefconfig`: BusyBox もカーネルと同じ Kconfig なので、`cml1.bbclass` がこれらを足している
- `listtasks` には `_setscene` の付いたタスクも出る（`do_package_setscene` など）。sstate から結果を取り出すタスクで、7 で見る
- `do_clean` は `tmp/work` の作業場所だけを消す。`do_cleansstate` は sstate も、`do_cleanall` はダウンロードしたソースも消す

## 4. 変数の値と、それがどこで決まったか

```sh
bitbake -e busybox > busybox.env
grep -n '^SRC_URI=' busybox.env
```

`bitbake -e` は変数の最終的な値だけでなく、どのファイルのどの操作で値が変わったかも出す（`#` で始まる行）。

```sh
grep -B 30 '^SRC_URI=' busybox.env | grep '^#'
```

`SRC_URI` の履歴（パスは短くした）:

```
# $SRC_URI [7 operations]
#   append .../meta/conf/bitbake.conf:734
#     [vardepsexclude] "    APACHE_MIRROR     CPAN_MIRROR ..."
#   set .../meta/conf/bitbake.conf:745
#     ""
#   set .../meta/conf/documentation.conf:383
#     [doc] "The list of source files - local or remote. ..."
#   set .../meta/recipes-core/busybox/busybox_1.37.0.bb:70
#     "https://busybox.net/downloads/busybox-${PV}.tar.bz2;name=tarball            file://0001-depmod-Ignore-.debug-directories.patch ..."
#   :append[libc-musl] .../meta/recipes-core/busybox/busybox_1.37.0.bb:71
#     " file://musl.cfg"
#   :append[x86-64] .../meta/recipes-core/busybox/busybox_1.37.0.bb:72
#     " file://sha_accel.cfg"
#   set .../meta/recipes-core/busybox/busybox_1.37.0.bb:74
#     [tarball.sha256sum] "3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4"
```

- `SRC_URI` を決めたのは `busybox_1.37.0.bb` の 70 行目。`busybox.inc`（`do_configure` などの処理）では設定していない
- `bitbake.conf:745` で空に設定されたあと、レシピで上書きされている
- `:append[libc-musl]` と `:append[x86-64]` は、`OVERRIDES` に `libc-musl` や `x86-64` があるときだけ足される。今は glibc で aarch64 なので、どちらも足されない（最終的な値に `musl.cfg` はない）
- `[doc]`、`[tarball.sha256sum]` は変数フラグ（`SRC_URI[tarball.sha256sum]`）。値とは別に変数に付けられる情報
- `bitbake -e` は 1 つのレシピで 3 万行ほど出る（busybox は 29844 行）。値だけなら `bitbake-getvar -r busybox SRC_URI` のほうが短い

## 5. BusyBox の設定を aarch64-boot-lab と比べる

aarch64-boot-lab は `defconfig` に `CONFIG_STATIC=y`・`tc` 無効を足した。Yocto の BusyBox は、レシピの `sources/defconfig`（BusyBox 本体の `make defconfig` とは別物）に、`SRC_URI` にある `.cfg`（`getopts.cfg`、`syslog.cfg` など）を `merge_config.sh` で重ねて作る（`busybox.inc` の `do_configure`）。

```sh
B=tmp/work/cortexa57-poky-linux/busybox/1.37.0/sources/busybox-1.37.0
diff <(grep '^CONFIG_' ~/aarch64-boot-lab/configs/busybox-1.32.config | sort) \
     <(grep '^CONFIG_' $B/.config | sort) | head -50
```

有効な項目（`=y`）の数は、aarch64-boot-lab が 850 個、Yocto が 413 個。Yocto は半分ほどしか有効にしていない。できたコマンドの数も、aarch64-boot-lab の 396 個（`_install/` のリンクの数）に対して、Yocto は 188 個。

目立つ違い:

| 項目 | aarch64-boot-lab | Yocto | 理由 |
|---|---|---|---|
| `CONFIG_STATIC` | `y` | なし | Yocto は glibc に動的リンクする（`libc6` はイメージに入っている） |
| `CONFIG_INIT` | `y` | なし | Poky の init は sysvinit（`INIT_MANAGER = "sysvinit"`） |
| `CONFIG_MDEV` | `y` | なし | デバイスファイルは eudev（`udevd`）が作る |
| `CONFIG_HUSH` | `y` | なし | シェルは ash だけ |
| `CONFIG_TC` | なし | なし | どちらも無効（aarch64-boot-lab は「新しいカーネルヘッダーではビルドが通らない」ので外した。Yocto のレシピには `busybox-1.36.1-no-cbq.patch` もある） |
| `CONFIG_FEATURE_SUID` | `y` | `y` | 同じ。Yocto はさらに setuid の要るコマンドを別のバイナリにする |

`init.cfg` と `mdev.cfg` は、条件が合うときだけ `SRC_URI` に入る（`busybox_1.37.0.bb`）。

```
${@["", "file://init.cfg"][(d.getVar('VIRTUAL-RUNTIME_init_manager') == 'busybox')]}
${@["", "file://mdev.cfg"][(d.getVar('VIRTUAL-RUNTIME_dev_manager') == 'busybox-mdev')]}
```

`${@...}` は Python の式で、`bitbake -e` で値を出すときに評価される。init を BusyBox にすると（8 章の DISTRO で試せる）、`init.cfg` が入って `CONFIG_INIT=y` になる。

大きさ:

| | aarch64-boot-lab | Yocto |
|---|---|---|
| `busybox` | 2.1MB（静的、strip 済み） | `busybox.nosuid` 658KB + `busybox.suid` 68KB（動的、strip 済み） |

## 6. イメージに何が入ったか

```sh
ls -l tmp/deploy/images/qemuarm64/
cat tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.rootfs.manifest
```

- `*.manifest`: イメージに入ったパッケージの一覧
- `*.qemuboot.conf`: `runqemu` が読む設定（1 章で使った）
- `Image`: カーネル（aarch64-boot-lab の `arch/arm64/boot/Image` と同じ形式）

大きさとパッケージの数は 1 章の「できたもの」に書いた（manifest は 32 パッケージ、ext4 は展開して 23MB、`Image` は 23MB）。

## 7. sstate の効果を測る

`tmp/` を消して、もう一度ビルドする。ビルドの結果は `SSTATE_DIR`（`bitbake-builds/.sstate-cache/`）にキャッシュされているので、コンパイルせずに取り出すだけになる。

```sh
rm -rf tmp
time bitbake core-image-minimal
```

最初に表示される `Sstate summary` を、1 章のとき（`Wanted 2287 Local 0 ... Missed 2287`）と比べる。

このリポジトリでは `./build.sh` で実行した（`rm -rf bitbake-builds/poky-wrynose/build/tmp` のあと `./build.sh`）。

```
start 2026-11-01 22:54:56
...
Sstate summary: Wanted 2287 Local 2282 Mirrors 0 Missed 5 Current 0 (99% match, 0% complete)
...
NOTE: Tasks Summary: Attempted 4331 tasks of which 4316 didn't need to be rerun and all succeeded.
end 2026-11-01 23:00:31
exit=0
```

| | 1 章の最初のビルド | `tmp/` を消したあと |
|---|---|---|
| `Sstate summary` | `Local 0 ... Missed 2287` | `Local 2282 ... Missed 5` |
| 実行したタスク | 4331 個すべて | 15 個（ほかは sstate から取り出した） |
| 時間 | 8 時間 12 分 | **5 分 35 秒** |
| `tmp/` の大きさ | 62GB（`work/` 50GB） | 5.3GB（`work/` 188MB） |

- `Local 2282`: 2287 個のうち 2282 個の結果が `bitbake-builds/.sstate-cache/` に見つかった。コンパイルせず、`do_<タスク>_setscene`（取り出すタスク）で戻した
- 実際に実行したのは、`core-image-minimal` のイメージを作るタスク（`do_rootfs`、`do_image_ext4`、`do_image_tar`、`do_image_complete` など）と、`qemu-helper-native` の `do_addto_recipe_sysroot`。`do_rootfs` はもともと sstate に入らないタスク
- `Missed 5` の 5 個が具体的にどのタスクかは、まだ調べていない（`do_image_complete` や SBOM のタスクなど、イメージ側のもののはず）
- `tmp/work/` が 188MB しかないのは、sstate から戻すのが「ほかのレシピやイメージに渡すもの」（`sysroots-components/`、`deploy/`、`pkgdata/`）だけだから。BusyBox の作業場所（`tmp/work/cortexa57-poky-linux/busybox/1.37.0/`）を見ると、`sources/` も `image/` もなく、`deploy-rpms/`・`pkgdata-pdata-input/`・`spdx/`・`temp/` などだけがある。2 のようにソースやビルドの途中のファイルを見たいときは、`bitbake -c compile -f busybox` などでタスクを実行し直す
- できたイメージは前と同じように起動した（`uname -r` は `6.18.54-yocto-standard`、`/bin/busybox.suid` には setuid ビットが付いている）

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

作業ディレクトリを汚さないよう、別のディレクトリで実行するとよい（`bitbake -g` はカレントディレクトリにファイルを書く）。数秒で終わり、`pn-buildlist`（3.8KB）と `task-depends.dot`（2.2MB）ができる。

- `pn-buildlist` は 273 行。1 章のビルドで `buildstats` に記録されたレシピの数（273）と同じ
- `busybox.do_compile` の依存は、同じレシピの 2 つのタスクだけ。

```
"busybox.do_compile" -> "busybox.do_configure"
"busybox.do_compile" -> "busybox.do_configure_ptest_base"
```

ほかのレシピ（コンパイラや glibc）への依存は `do_prepare_recipe_sysroot` に付いていて、`do_configure` を通して間接的に効く。

### なぜ llvm-native がビルドされたか

1 章のビルドで一番時間がかかったのは `llvm-native` と `clang-native`（合わせて 5 時間）だった。イメージには入っていないのに、なぜビルドされたかを依存関係から追う。

```sh
grep -E '^"[a-z0-9.-]+\.do_[a-z_]+" -> "llvm-native\.' task-depends.dot | cut -d' ' -f1 | sort -u
bitbake-getvar -r qemu-system-native PACKAGECONFIG
bitbake-getvar -r mesa-native PACKAGECONFIG
```

1 章で `bitbake-getvar` を使って確かめたところまで:

```
qemu-system-native  PACKAGECONFIG: fdt alsa kvm pie slirp png pixman sdl virglrenderer epoxy
  → mesa-native     PACKAGECONFIG: ... gallium-llvm libclc ...（DEPENDS に llvm-native）
    → llvm-native, clang-native（clang は libclc から。このあとで追う）
```

`task-depends.dot` で、それぞれのレシピに依存しているレシピを数える。

```
llvm-native         ← clang-native, mesa-native, mesa-tools-native, spirv-llvm-translator-native, core-image-minimal
clang-native        ← libclc-native, core-image-minimal
libclc-native       ← mesa-tools-native
mesa-tools-native   ← mesa-native
mesa-native         ← libepoxy-native, libsdl2-native, virglrenderer-native, core-image-minimal
qemu-system-native  ← qemu-helper-native, core-image-minimal
```

（`core-image-minimal` が全部に出てくるのは、SBOM とライセンスのタスクが、使ったレシピすべてに依存するから）

イメージが QEMU に依存する理由は `qemuboot.bbclass` にある。

```
# openembedded-core/meta/classes-recipe/qemuboot.bbclass:193
EXTRA_IMAGEDEPENDS += "qemu-system-native qemu-helper-native:do_addto_recipe_sysroot"
```

`task-depends.dot` で見ると、イメージを作り終えるタスクが、QEMU のできるのを待っている。

```
"core-image-minimal.do_image_complete" -> "qemu-helper-native.do_addto_recipe_sysroot"
"core-image-minimal.do_image_complete" -> "qemu-system-native.do_populate_sysroot"
```

QEMU に画面の機能（virglrenderer、epoxy）が入る理由は `qemu-system-native_10.2.0.bb` にある。

```
PACKAGECONFIG ??= "fdt alsa kvm pie slirp png pixman sdl \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'virglrenderer epoxy', '', d)} \
```

Poky の `DISTRO_FEATURES` には `opengl` が入っている（`x11`、`wayland`、`vulkan` も）。まとめると:

```
core-image-minimal（qemuboot.bbclass の EXTRA_IMAGEDEPENDS）
  → qemu-system-native（DISTRO_FEATURES の opengl で virglrenderer・epoxy、既定で sdl）
    → mesa-native
        PACKAGECONFIG の gallium-llvm → llvm-native
        PACKAGECONFIG の libclc       → mesa-tools-native → libclc-native → clang-native
                                                           （spirv-llvm-translator-native、spirv-tools-native も）
```

<!-- TODO: qemu-system-native の virglrenderer・epoxy・sdl を外す（PACKAGECONFIG:remove:pn-qemu-system-native）と llvm が要らなくなるか、
bitbake -g の pn-buildlist で比べる。外すと runqemu の画面（nographic でないとき）がどうなるかも書く -->
