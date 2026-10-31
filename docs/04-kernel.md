# 4 章: カーネルのカスタマイズ

aarch64-boot-lab では `make defconfig` でビルドし、`.config` を `configs/` に保存した。Yocto では、カーネルを linux-yocto のレシピでビルドし、設定とパッチを 3 章の `meta-practice` に置く。

> **下書き**: レシピの中身（版・ブランチ・コミット）はソースで確かめた。手順の出力はまだ確かめていない。

## 1. Wrynose の linux-yocto

`openembedded-core/meta/recipes-kernel/linux/` にあるカーネルのレシピ:

| レシピ | 内容 |
|---|---|
| `linux-yocto_6.18.bb` | 標準。qemuarm64 はこれを使う |
| `linux-yocto-rt_6.18.bb` | PREEMPT_RT（リアルタイム）版 |
| `linux-yocto-tiny_6.18.bb` | サイズ優先の版 |
| `linux-yocto-dev.bb` | 開発中の最新（`PREFERRED_PROVIDER` で選ぶ） |

`linux-yocto_6.18.bb` の中身:

```
KBRANCH:qemuarm64 ?= "v6.18/standard/base"
LINUX_VERSION ?= "6.18.54"
SRC_URI = "git://git.yoctoproject.org/linux-yocto.git;name=machine;branch=${KBRANCH};protocol=https \
           git://git.yoctoproject.org/yocto-kernel-cache;type=kmeta;name=meta;branch=yocto-6.18;destsuffix=${KMETA};protocol=https"
```

- 版は **6.18.54**。aarch64-boot-lab の `linux-6.18.53` とほぼ同じ
- **Wrynose の openembedded-core には 6.18 しかない**。aarch64-boot-lab のように 5.4 / 7.2 に切り替えるには、自分でレシピを書く必要がある（このあとの「5. 版を切り替える」）
- ソースは 2 つ。カーネル本体（`linux-yocto.git`）と、設定の断片を集めた `yocto-kernel-cache`（kmeta）
- `.config` は `defconfig` ではなく、`yocto-kernel-cache` の `.scc` / `.cfg` を重ねて作る

## 2. `.config` を aarch64-boot-lab と比べる

```sh
bitbake -c kernel_configme virtual/kernel    # .config を作るところまで
K=$(bitbake -e virtual/kernel | sed -n 's/^B="\(.*\)"/\1/p')
diff <(grep '^CONFIG_' ~/aarch64-boot-lab/configs/linux-6.18.53.config | sort) \
     <(grep '^CONFIG_' $K/.config | sort) | wc -l
```

見るところ:
- 有効なドライバの数（`defconfig` は多くの SoC のドライバを有効にしている。linux-yocto の qemuarm64 は QEMU に必要なものに絞っている）
- `CONFIG_DEBUG_INFO`（9 章の gdb で使う）
- `CONFIG_NFSD`（`qemu.inc` で `features/nfsd/nfsd-enable.scc` が足されている）

<!-- TODO: 行数と、目立つ違い -->

## 3. config fragment で設定を変える

aarch64-boot-lab の `make menuconfig` に相当する。

```sh
bitbake -c menuconfig virtual/kernel     # 端末が必要。変更して保存する
bitbake -c diffconfig virtual/kernel     # 変更した分だけを fragment.cfg に書き出す
```

`diffconfig` が出力した場所を表示するので、それを `meta-practice` にコピーする。

```
meta-practice/recipes-kernel/linux/
├── linux-yocto_%.bbappend
└── files/
    └── practice.cfg
```

`linux-yocto_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://practice.cfg"
```

例として、起動ログで確かめやすい設定を変える:

```
# practice.cfg
CONFIG_LOCALVERSION="-practice"
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
```

- `CONFIG_LOCALVERSION`: `uname -r` と起動ログの `Linux version` に付く
- `CONFIG_IKCONFIG_PROC`: `/proc/config.gz` で、動いているカーネルの設定を読める

```sh
bitbake virtual/kernel && bitbake core-image-minimal
runqemu qemuarm64 nographic slirp
# ゲストで
uname -r
zcat /proc/config.gz | grep LOCALVERSION
```

`do_kernel_configcheck` が、fragment に書いた設定が最終的な `.config` に入らなかったときに警告を出す（依存する設定が足りないときなど）。

<!-- TODO: uname -r の結果、configcheck の警告が出るか -->

## 4. パッチを当てる

`start_kernel` に `pr_info` を 1 行足し、起動ログに出ることを確かめる。

### devtool で編集する

```sh
devtool modify linux-yocto               # workspace/sources/linux-yocto にソースを展開
cd workspace/sources/linux-yocto
# init/main.c の start_kernel() の先頭近くに足す:
#   pr_info("yocto-practice: hello from start_kernel\n");
git commit -am "init: start_kernel でメッセージを出す"
cd -
devtool build linux-yocto
bitbake core-image-minimal
runqemu qemuarm64 nographic slirp        # dmesg | grep yocto-practice
devtool finish linux-yocto ../../../meta-practice   # パッチにして meta-practice に書き出す
```

- `devtool modify` の間は、レシピの代わりに `workspace/sources/` のソースでビルドされる
- `devtool finish` は、コミットを `0001-*.patch` にして bbappend の `SRC_URI` に足し、workspace から外す

<!-- TODO: devtool finish が作ったファイル、dmesg の出力 -->

## 5. 版を切り替える

aarch64-boot-lab では 5.4.83 / 6.18.53 / 7.2.7 を比べた。Wrynose には 6.18 しかないので、ほかの版を使うには次のどちらかにする。

| 方法 | 内容 | 向いている場合 |
|---|---|---|
| A. kernel.org のカーネルのレシピを書く | `inherit kernel` で `linux-practice_7.2.bb` を作り、`defconfig` を使う。`PREFERRED_PROVIDER_virtual/kernel = "linux-practice"` で選ぶ | aarch64-boot-lab と同じ版・同じ `defconfig` で比べたい |
| B. `linux-yocto-dev` を使う | 開発中の linux-yocto。版は自分で選べない | 新しい版をとりあえず試したい |

この章では A をやる。aarch64-boot-lab と同じ `linux-7.2.7.tar.xz` を使い、`configs/linux-7.2.7.config` を `defconfig` として渡す。

<!-- TODO: linux-practice_7.2.bb を書いて確かめる。5.4.83 は gcc 15 でビルドが通るかが分からない（aarch64-boot-lab は gcc 13.3.0） -->

## 6. ビルドし直しの量

カーネルの設定を変えても、ユーザーランド（glibc や BusyBox）はビルドし直さない。カーネルと、カーネルに依存するもの（カーネルモジュール、イメージ）だけ。

```sh
bitbake core-image-minimal 2>&1 | grep 'Sstate summary'
```

<!-- TODO: 設定変更前後の Sstate summary とビルド時間 -->
