#!/bin/bash

# ビルドする。ログを logs/build-<ターゲット>-<MACHINE>.log に残す（開始・終了の時刻と終了コードも書く）。
#   ./build.sh                          core-image-minimal を今の MACHINE でビルド
#   ./build.sh -m raspberrypi4-64       MACHINE を変えてからビルド
#   ./build.sh u-boot

usage() {
    cat <<EOF
使い方: $0 [オプション] [ターゲット]

ターゲット: bitbake に渡すもの（省略すると core-image-minimal）

オプション:
  -m, --machine MACHINE   MACHINE を変える（bitbake-config-build enable-fragment machine/MACHINE）。
                          変えた MACHINE は conf/toolcfg.conf に残り、次のビルドでも使われる
  -h, --help              この説明を表示する
EOF
}

set -e
cd "$(dirname "$0")"

# ---- 引数 ----
NEW_MACHINE=
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--machine) [ $# -ge 2 ] || { usage >&2; exit 1; }; NEW_MACHINE=$2; shift 2 ;;
        --machine=*)  NEW_MACHINE=${1#*=}; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "不明なオプション: $1" >&2; usage >&2; exit 1 ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done
[ ${#ARGS[@]} -le 1 ] || { usage >&2; exit 1; }
TARGET=${ARGS[0]:-core-image-minimal}

. ./env.sh

if [ -n "$NEW_MACHINE" ]; then
    bitbake-config-build enable-fragment --quiet machine/$NEW_MACHINE
fi
MACHINE=$(lab_machine)

# ---- ログ ----
mkdir -p "$LAB_LOGS"
LOG=$LAB_LOGS/build-$TARGET-$MACHINE.log
echo "== bitbake $TARGET（MACHINE=$MACHINE）、ログ: ${LOG#$LAB_TOP/} =="
date '+start %F %T' > "$LOG"
set +e
bitbake "$TARGET" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
set -e
date '+end %F %T' >> "$LOG"
echo "exit=$RC" >> "$LOG"
exit $RC
