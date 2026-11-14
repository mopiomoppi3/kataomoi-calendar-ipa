# 片思いカレンダー IPAスターター

ユーザーが 2026-11-14 にアップロードした片思いカレンダー (`index.html`) を
WKWebView で包んだ Xcodeプロジェクト + GitHub Actions で署名なしIPAを作る workflow。
アプリ表示名「片思いカレンダー」、Bundle ID は仮で `com.moppi.kataomoi`。

## 中身
- `KataomoiCalendar/` … プロジェクト本体。`index.html` はアップロードされたこのバージョンそのまま
- `.github/workflows/build-ipa.yml` … GitHubの macos-26 マシン（Xcode 26）で署名なしIPAをビルド
- バックアップ書き出し（ダウンロード）は WKDownload で受けて共有シートに渡す実装入り

## やり方（MacにXcodeを入れない）
1. GitHubで新しいリポジトリを作り、このフォルダの中身を全部上げる（.github が直下に来ること）
2. Actions タブでビルドが走る
3. 終わったら `KataomoiCalendar-unsigned` の成果物から `.ipa` をダウンロード
4. iPhone側で Feather などで署名してインストール（無料Apple IDの署名は7日で切れる）

## 注意
- データ移行：今のWeb版（ホーム画面ショートカット等）の記録は自動では移らない。
  先に今の版でバックアップを書き出して、IPA版を入れた後に読み込むこと
- 記録の保存先は localStorage（WKWebViewの永続ストア）。アプリを消すと記録も消えるので
  バックアップ書き出しが保険になる
- フォントは Google Fonts を読むので、表示にはネットが要る（切れると代替フォント表示）
- ネイティブ部品は無い画面構成なので Liquid Glass は画面自体には付かない（ビルドは iOS 26 SDK）
- このプロジェクトは macOS / GitHub Actions でのビルド確認はまだしていない。初回はログを見て直す前提

## タブバー（ネイティブ標準）
- ルートは標準の UITabBarController。カスタムの外観指定は一切していないので、
  iOS 26 SDKでビルドして iOS 26以上で動かすと、デフォルトの Liquid Glass タブバーになる
  （iOS 26未満では従来デザインに自動で戻る）
- 中身の WKWebView は1つを全タブで共有。HTML側のタブバーは注入スクリプトで非表示化し、
  ネイティブのタップはページの showTab() に連携する
- ページ内で起きたタブ移動（カードからカレンダーへ等）や、設定でのタブ名変更・タブ表示オフも
  注入スクリプト経由でネイティブ側に同期する。アイコンは SF Symbols の標準アイコン
- 設定画面のようなタブ外の画面では、タブの選択は直前のままになる
