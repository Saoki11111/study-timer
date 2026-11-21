# StudyTimer

勉強用の、Macのメニューバー専用ストップウォッチ。M1/M2/M3・Intel 両対応の想定（ビルドしたMacのアーキテクチャで生成）。

- 左クリック：勉強開始 → 休憩に切り替え（休憩タイマーが0から数え始める）→ 勉強に戻る。勉強の表示は「今日の勉強時間」で、日付が変われば自動で0から（手動リセットなし）
- メニューバー表示：勉強中は `▶ 12:34`、休憩中は `☕ 05:32`、両方止めているときは `❚❚ 12:34`
- 右クリック：メニュー（Study Today / Break Today / Study This Week〈月曜始まり〉/ Study This Month、Open Report、Stop Both Timers、Quit）
- Open Report：Mac 内だけでレポート（HTML）を生成してブラウザで開く。内容は、今日・今週・今月・累計のカード、今日の内訳ドーナツ（勉強 vs 休憩）と直近15週のヒートマップ（左右に並べて表示）、今月のカレンダー（各日に勉強・休憩の時間入り）、月ごとの合計リスト。ネットには送信しない
- ウィンドウは出ないが、Dock にはアイコンが出る（落ちたときの再起動を Dock の1クリックでできるように）。ログイン時の自動起動が要る場合は、Dock のアイコンを右クリック → オプション →「ログイン時に開く」で macOS 標準のまま設定できる
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
