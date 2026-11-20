# StudyTimer

勉強用の、Macのメニューバー専用ストップウォッチ。M1/M2/M3・Intel 両対応の想定（ビルドしたMacのアーキテクチャで生成）。

- 左クリック：勉強開始 → 休憩に切り替え（休憩タイマーが0から数え始める）→ 勉強に戻る
- メニューバー表示：勉強中は `▶ 12:34`、休憩中は `☕ 05:32`、両方止めているときは `❚❚ 12:34`
- 右クリック：メニュー（Study Today / Break Today / Study This Week〈月曜始まり〉/ Study This Month、Stop Both Timers、Reset Timer、Quit）
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
