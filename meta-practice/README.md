# meta-practice

yocto-practice-lab の自作レイヤー。ボードに依存しないもの（ディストリビューション、イメージ、アプリ、カーネルの共通の設定）を置く。ボードに関するものは `meta-practice-bsp`。

- レイヤー名（`BBFILE_COLLECTIONS`）: `practice`
- 対応するリリース: Wrynose

## フラグメント

`conf/fragments/<名前>.conf` は `practice/<名前>` として有効にできる。

```sh
bitbake-config-build list-fragments
bitbake-config-build enable-fragment practice/lowmem
bitbake-config-build disable-fragment practice/lowmem
```

| フラグメント | 内容 |
|---|---|
| `practice/lowmem` | 並列数を 2 に下げる（RAM 7GB 用） |
