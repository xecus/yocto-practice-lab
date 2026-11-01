# meta-practice-bsp

yocto-practice-lab の自作レイヤー。ボード（ハードウェア）に関するものを置く。ボードに依存しないものは `meta-practice`。

- レイヤー名（`BBFILE_COLLECTIONS`）: `practice-bsp`
- 対応するリリース: Wrynose

| 置くもの | 章 |
|---|---|
| U-Boot のブートスクリプト、wks、`QB_*`（フラグメント `practice-bsp/uboot`） | 5 |
| TF-A の設定、`qemuarm64-tfa` | 6 |
| CPU ごとの MACHINE（`practice-a72` など） | 8 |
| デバイスツリー、カーネルの BSP の記述 | 10 |

まだ中身はない。各章を確かめるときに足す。
