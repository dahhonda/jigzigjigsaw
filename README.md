# じぐじぐじぐそー (jig zig jigsaw)

 [jig.jp Engineers' Blog Advent Calendar 2025](https://adventar.org/calendars/11721) の12月12日分の記事
 「jig社員がZig言語でジグソーパズルを作ってみた」のコードです。


 ## ビルド・起動方法

Zigをインストールします。

```sh
brew install zig
```

本記事執筆時点でのZigのバージョンです。

```sh
zig version
0.15.2
```

以下のコマンドでビルドと起動ができます。

```sh
zig build run
```

ビルドされた実行ファイルは `./zig-out/bin/` に出力されるので、以下のコマンドで起動できます。

```sh
./zig-out/bin/jigzigjigsaw
```

ブラウザで動作するWASMビルドと起動ができます。

```sh
zig build run -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast
```

ビルドされた実行ファイルは `./zig-out/web/` に出力されるので、GitHub Pagesで公開できます。

https://{username}.github.io/{repository}/zig-out/web/jigzigjigsaw.html

## 動作環境

以下の環境でビルドと動作を確認しました。たぶんIntel MacとかWindowsとかLinuxとかでも動くと思います

- MacBook Pro 14インチ, 2024 
    - チップ: Apple M1 Pro
    - メモリ: 16 GB
    - macOS: Sequoia 15.6.1


## 今すぐプレイ

弊社創業者の福野([@taisukef](https://github.com/taisukef))さんが、WASMビルド対応とGitHub Pagesでの公開をしてくださいました。
下記のURLからプレイできます！

https://taisukef.github.io/jigzigjigsaw/zig-out/web/jigzigjigsaw.html


福野さんありがとうございました！

