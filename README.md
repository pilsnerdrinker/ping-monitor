# PingMonitor

FF14 のデータセンター（DC）への ping 品質を、複数まとめて監視できる軽量アプリです。
ゲーム中も邪魔にならない小さなオーバーレイに、現在の ms・損失率・推移グラフを表示します。
インストール不要、Windows 用。

## ダウンロード

[Releases](../../releases) から `PingMonitor.exe` をダウンロードしてください。
**この exe 1 つだけで動きます**（インストールや他のファイルは不要です）。
初回起動時に「WindowsによってPCが保護されました」と表示される場合は、「詳細情報」→「実行」で起動できます（下記「注意」参照）。

---

## できること

- FF14 の 4 DC（Elemental / Gaia / Mana / Meteor）をプリセット済み。IP は追加・編集・削除できます
- 各 DC を同時に監視。連続（-t、初期設定）と回数指定（-n）を選べます
- 一覧に 最小 / 最大 / 平均 / 損失率 をリアルタイム表示
- 常に手前に出る小さなオーバーレイ：DC 名・現在の ms（大きく表示）・min/max/avg・損失率・推移グラフ（スパークライン）
- 回線品質を色で判定（下記）
- 測定結果を CSV で書き出し（時刻つき。あとで分析に使えます）
- 設定（IP・名前・色・並び順・チェック状態・モード・オーバーレイ位置）は自動保存され、次回起動時に復元されます

## 品質の判定（オーバーレイ左の●の色）

| 色 | 判定 | 目安 |
|----|------|------|
| 水色 | EXCELLENT | 損失 0%・最大 20ms 未満 |
| 緑 | GOOD | 損失 0%・最大 100ms 未満 |
| 黄 | OK-ish | 最大 100〜200ms |
| 赤 | BAD | 損失あり、または最大 200ms 超 |

判定は直近 30 回分の測定を見て決まります。

## 使い方

1. `PingMonitor.exe` をダブルクリックで起動します
   （ソースから動かす場合は `PingMonitor.bat` をダブルクリック、または `PingMonitor.ps1` を右クリック →「PowerShell で実行」）
2. 測りたい DC にチェックを入れる（起動時は全部チェック済み。左上の「All」で全選択／全解除）
3. モード（-t 連続（止めるまで動き続ける） / -n 回数（指定回数で自動停止））を選んで緑のボタン「Start selected」を押す
4. オーバーレイ（小窓）は起動時に自動で表示されます。「Overlay」ボタンで表示／非表示を切り替え。ドラッグで移動、マウスホイールで濃さ調整、右クリックで閉じる
5. 止めるときは赤いボタン「STOP ALL」を押す。「Export CSV」で結果を保存できます

### 行の編集

- 名前・IP のセルを **右クリック**すると、その場で書き換えられます（Enter で確定）
- 一番右の色セルを **右クリック**すると、グラフの色を変えられます
- 「↑」「↓」で並び順を変更できます（オーバーレイの表示順にも反映されます）
- 「Reset」で、プリセットの 4 DC に戻せます（確認あり）

### オーバーレイの表示対象

- オーバーレイには「チェックが入っていて、かつ測定中の DC」が表示されます
- チェックを外すとオーバーレイから消えます。もう一度表示するにはチェックを入れて「Start selected」を押してください

## 注意

- **IP は変わることがあります。** うまく測れない DC は、実際の接続先に合わせて IP を編集してください。実際にゲームが通信している IP は、コマンドプロンプトの `netstat` でも調べられます
- 設定は `%APPDATA%\PingMonitor\settings.json` に保存されます。すべてリセットしたいときはこのファイルを削除してください（アプリ内の「Reset」は DC 一覧を初期化します）
- exe 版は、ウイルス対策ソフトに誤検知されることがあります（スクリプトを exe 化しているため）。心配な場合は、同梱の `PingMonitor.ps1`（ソース）の中身を確認できます

## 動作環境

Windows 10 / 11（Windows PowerShell 5.1 で動作確認）

## ライセンス

MIT License

---
---

# PingMonitor (English)

A lightweight tool to monitor ping quality to FF14 data centers (DCs), several at once.
It shows the current ms, packet loss, and a trend graph in a small always-on-top overlay
that stays out of your way while gaming. No installation required. For Windows.

## Download

Get `PingMonitor.exe` from [Releases](../../releases).
**The single exe is all you need** — no installation, no other files required.
On first launch, Windows may show "Windows protected your PC" — click "More info" → "Run anyway" (see Notes below).

## Features

- Presets for the 4 FF14 DCs (Elemental / Gaia / Mana / Meteor). IPs can be added, edited, or removed
- Monitor multiple DCs at once, in continuous mode (-t, default) or count mode (-n)
- Live min / max / average / loss in the list
- Small always-on-top overlay: DC name, current ms (shown large), min/max/avg, loss %, and a sparkline
- Color-coded quality verdict (see below)
- Export results to CSV (with timestamps) for later analysis
- Settings (IPs, names, colors, order, check state, mode, overlay position) are saved automatically and restored on next launch

## Quality verdict (the dot left of each name)

| Color | Verdict | Guideline |
|-------|---------|-----------|
| Cyan | EXCELLENT | 0% loss, max < 20ms |
| Green | GOOD | 0% loss, max < 100ms |
| Yellow | OK-ish | max 100–200ms |
| Red | BAD | any loss, or max > 200ms |

The verdict is based on the most recent 30 samples.

## How to use

1. Double-click `PingMonitor.exe` to launch
   (or, to run from source: double-click `PingMonitor.bat`, or right-click `PingMonitor.ps1` → "Run with PowerShell")
2. Check the DCs you want to measure (all checked at startup; use "All" at the top-left to select/clear all)
3. Pick a mode (-t continuous / -n count) and click "Start selected"
4. The overlay (small window) appears automatically on startup. Use the "Overlay" button to toggle it. Drag to move, mouse wheel to change opacity, right-click to close
5. Click "STOP ALL" to stop. Use "Export CSV" to save results

### Editing rows

- **Right-click** a Name or IP cell to edit it in place (Enter to confirm)
- **Right-click** the color cell (far right) to change the graph color
- Use "↑" / "↓" to reorder (the overlay follows the same order)
- "Reset" restores the default 4 DCs (with confirmation)

### What the overlay shows

- The overlay shows DCs that are checked **and** currently being measured
- Unchecking a DC removes it from the overlay. To show it again, check it and click "Start selected"

## Notes

- **IPs can change.** If a DC won't measure correctly, edit its IP to the actual endpoint. You can find the IP your game is really talking to with `netstat` in Command Prompt
- Settings are stored in `%APPDATA%\PingMonitor\settings.json`. Delete that file to reset everything (the in-app "Reset" only resets the DC list)
- The exe build may be flagged by antivirus software (because it wraps a script). If concerned, you can review the included `PingMonitor.ps1` source

## Requirements

Windows 10 / 11 (tested on Windows PowerShell 5.1)

## License

MIT License
