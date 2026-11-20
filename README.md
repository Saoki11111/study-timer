# StudyTimer

勉強用の、Macのメニューバー専用ストップウォッチ。M1/M2/M3・Intel 両対応の想定（ビルドしたMacのアーキテクチャで生成）。

- 左クリック：開始 / 一時停止
- 右クリック：メニュー（Today / This Week〈月曜始まり〉/ This Month の合計、Reset Timer、Quit）
- ダブルクリックではリセットしない。ウィンドウも枠線もDockアイコンもなし
- 合計は1秒ごとに Mac 内に保存（`~/Library/Application Support/StudyTimer/data.json`）。アカウント不要

## ダウンロードして使う

Releases の **latest** から `StudyTimer.dmg` をダウンロード → 開いて StudyTimer をアプリケーションフォルダへドラッグ → 起動。

※ 個人制作の未署名アプリのため、初回だけ macOS の確認が出ます：
「完了」→ システム設定 → プライバシーとセキュリティ →「このまま開く」。2回目からは出ません。
この確認を完全になくすには Apple Developer Program（年99ドル）での署名と公証が必要で、個人用では割に合わないためしていません。

## 自分でビルドする

```bash
./build_app.sh
open ./StudyTimer.app
```

Xcode Command Line Tools が必要です（`xcode-select --install`）。

GitHub Actions でも main への push のたびに自動ビルドされ、Releases の latest に zip と dmg が付きます。

## ファイル

- `main.swift` — 本体（AppKit、単一ファイル）
- `Info.plist` — アプリ情報（LSUIElement = Dockに出ない）
- `AppIcon.icns.b64` — アイコン（base64テキストで保管、`build_app.sh` が復元）
- `make_icon.py` — アイコン生成スクリプト（Pillow）
