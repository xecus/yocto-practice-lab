# source して使う。bitbake-setup の venv を有効にし、ビルドディレクトリに入って init-build-env を読む。
#   . ./env.sh
# setup.sh / build.sh / run.sh もこのファイルを読み込む。

if [ -n "$BASH_SOURCE" ]; then
    LAB_TOP=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
else
    LAB_TOP=$(pwd)
fi
LAB_SETUP=$LAB_TOP/bitbake-builds/poky-wrynose
LAB_BUILD=$LAB_SETUP/build
LAB_LOGS=$LAB_TOP/logs

if [ ! -f "$LAB_BUILD/init-build-env" ]; then
    echo "$LAB_BUILD がありません。先に ./setup.sh を実行してください" >&2
    return 1 2>/dev/null || exit 1
fi

. "$LAB_TOP/bitbake-setup-venv/bin/activate"
cd "$LAB_BUILD"
. ./init-build-env > /dev/null

# 今の MACHINE を toolcfg.conf の machine/ フラグメントから読む（bitbake -e より速い）。
# toolcfg.conf のコメントにも "machine/<name>" があるので、OE_FRAGMENTS の行だけを見る。
lab_machine() {
    sed -n '/^OE_FRAGMENTS/s/.*[" ]machine\/\([^ "]*\).*/\1/p' "$LAB_BUILD/conf/toolcfg.conf" 2> /dev/null | tail -1
}
