#!/bin/bash

# Yocto でビルドしたイメージを runqemu で起動する。aarch64-boot-lab の run.sh と同じ形。
#   ./run.sh direct
#   ./run.sh direct --cpu a72 --smp 1
#   ./run.sh direct-debug              （別の端末で gdb-multiarch -x debug-6.18.gdb）
# 終了: ゲストで poweroff。QEMU ごと止めるなら Ctrl-a x。

usage() {
    cat <<EOF
使い方: $0 [オプション] <起動方法>

起動方法:
  direct          QEMU → カーネル（-kernel で直接渡す。ルートは ext4 のイメージ）
  direct-debug    direct と同じ。CPU を止めて gdb を待つ（-s -S、nokaslr）
  uboot           QEMU → U-Boot → boot.scr → カーネル（5 章で追加する）
  tfa             QEMU → TF-A → U-Boot → カーネル（6 章で追加する）

オプション:
  -m, --machine MACHINE   起動する MACHINE（省略すると、今のビルドの MACHINE）
  -i, --image IMAGE       起動するイメージ（省略すると core-image-minimal）
  -c, --cpu CPU           QEMU の -cpu（省略すると MACHINE の既定。cortex- は省いてもよい）
  -s, --smp N             CPU の数（省略すると MACHINE の既定。qemuarm64 は 4）
  -h, --help              この説明を表示する
EOF
}

set -e
cd "$(dirname "$0")"

# ---- 引数 ----
MACHINE_ARG=
IMAGE=core-image-minimal
CPU=
SMP=
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--machine) [ $# -ge 2 ] || { usage >&2; exit 1; }; MACHINE_ARG=$2; shift 2 ;;
        --machine=*)  MACHINE_ARG=${1#*=}; shift ;;
        -i|--image)   [ $# -ge 2 ] || { usage >&2; exit 1; }; IMAGE=$2; shift 2 ;;
        --image=*)    IMAGE=${1#*=}; shift ;;
        -c|--cpu)     [ $# -ge 2 ] || { usage >&2; exit 1; }; CPU=$2; shift 2 ;;
        --cpu=*)      CPU=${1#*=}; shift ;;
        -s|--smp)     [ $# -ge 2 ] || { usage >&2; exit 1; }; SMP=$2; shift 2 ;;
        --smp=*)      SMP=${1#*=}; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "不明なオプション: $1" >&2; usage >&2; exit 1 ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done
[ ${#ARGS[@]} -eq 1 ] || { usage >&2; exit 1; }
METHOD=${ARGS[0]}

. ./env.sh

MACHINE=${MACHINE_ARG:-$(lab_machine)}
DEPLOY=tmp/deploy/images/$MACHINE
# runqemu には MACHINE の名前ではなく qemuboot.conf を渡す。
# MACHINE の名前を渡すと runqemu は "MACHINE=qemuarm64 bitbake -e" を実行するが、
# Wrynose では machine/ フラグメントと MACHINE= の両方があるとエラーになる。
# qemuboot.conf を渡せば bitbake -e を実行しないので、ほかの MACHINE のイメージも起動できる。
QBCONF=$LAB_BUILD/$DEPLOY/$IMAGE-$MACHINE.rootfs.qemuboot.conf
[ -f "$QBCONF" ] || { echo "${QBCONF#$LAB_BUILD/} がありません。先に ./build.sh -m $MACHINE $IMAGE を実行してください" >&2; exit 1; }

# ---- QEMU に足す引数 ----
# runqemu は qemuparams を最後に付けるので、MACHINE の既定（QB_CPU・QB_SMP）より優先される
QEMUPARAMS=
BOOTPARAMS=
if [ -n "$CPU" ]; then
    case "$CPU" in
        cortex-*) ;;
        *) CPU=cortex-$CPU ;;
    esac
    QEMUPARAMS="$QEMUPARAMS -cpu $CPU"
else
    # qemuboot.conf の qb_cpu（例: "-cpu cortex-a57"）をログの名前に使う
    CPU=$(sed -n 's/^qb_cpu = -cpu \(.*\)/\1/p' "$QBCONF")
fi
if [ -n "$SMP" ]; then
    QEMUPARAMS="$QEMUPARAMS -smp $SMP"
else
    SMP=$(sed -n 's/^qb_smp = -smp \(.*\)/\1/p' "$QBCONF")
fi

case "$METHOD" in
    direct)
        ;;
    direct-debug)
        # QEMU は CPU を止めた状態（-S）で起動し、TCP 1234 番で gdb の接続を待つ（-s）。
        # nokaslr: vmlinux のシンボルアドレスと実行時アドレスを一致させるため
        QEMUPARAMS="$QEMUPARAMS -s -S"
        BOOTPARAMS="$BOOTPARAMS nokaslr"
        ;;
    uboot|tfa)
        echo "$METHOD はまだありません（uboot は 5 章、tfa は 6 章で追加する）" >&2
        exit 1
        ;;
    *)
        echo "起動方法が不正です: $METHOD" >&2
        usage >&2
        exit 1
        ;;
esac

# ---- ログ ----
NAME=$METHOD-$IMAGE-$MACHINE-$CPU-smp$SMP
mkdir -p "$LAB_LOGS"
LOG=$LAB_LOGS/boot-$NAME.log
echo "== image: $IMAGE、machine: $MACHINE、cpu: $CPU x ${SMP:-?}、ログ: ${LOG#$LAB_TOP/} ==" | tee "$LOG"
if [ "$METHOD" = direct-debug ]; then
    echo "== 別の端末で: gdb-multiarch -x debug-6.18.gdb ==" | tee -a "$LOG"
fi

# nographic: シリアルを端末につなぐ / slirp: ユーザーモードのネットワーク（tap と違い sudo が要らない）
# snapshot: ゲストでの書き込みを捨てる（QEMU の -snapshot）。qemuarm64 のイメージは ext4.zst だけで、
#           runqemu は .zst を snapshot のときだけ受け付ける（一時ファイルに展開し、終了時に消す）
RUNQEMU_ARGS=("$QBCONF" nographic slirp snapshot)
[ -z "$QEMUPARAMS" ] || RUNQEMU_ARGS+=("qemuparams=${QEMUPARAMS# }")
[ -z "$BOOTPARAMS" ] || RUNQEMU_ARGS+=("bootparams=${BOOTPARAMS# }")
runqemu "${RUNQEMU_ARGS[@]}" 2>&1 | tee -a "$LOG"
