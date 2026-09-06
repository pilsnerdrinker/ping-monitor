# PingMonitor

FF14 のデータセンター（DC）への ping 品質を、複数まとめて監視できる軽量ツールです。
ゲーム中もじゃまにならない小さなオーバーレイに、平均 ms・損失率・推移グラフを表示します。
インストール不要。Windows 用。

---

## できること

- FF14 の 4 DC（Elemental / Gaia / Mana / Meteor）をプリセット済み。IP は追加・編集・削除できます
- 各 DC を同時に監視。回数指定（-n）と連続（-t）を選べます
- 一覧に 最小 / 最大 / 平均 / 損失率 をリアルタイム表示
- 常に手前に出る小さなオーバーレイ：DC 名・平均 ms・損失率・推移グラフ（スパークライン）
- 回線品質を色で判定（下記）
- 測定結果を CSV で書き出し（時刻つき。あとで分析に使えます）
- 設定（IP・名前・色・並び順・チェック状態）は自動保存され、次回起動時に復元されます

## 品質の判定（オーバーレイ左の●の色）

| 色 | 判定 | 目安 |
|----|------|------|
| 水色 | EXCELLENT | 損失 0%・最大 20ms 未満 |
| 緑 | GOOD | 損失 0%・最大 100ms 未満 |
| 黄 | OK-ish | 最大 100〜200ms |
| 赤 | BAD | 損失あり、または最大 200ms 超 |

判定は直近 30 回分の測定を見て決まります。

## 使い方

1. `PingMonitor.bat` をダブルクリック（または `PingMonitor.ps1` を右クリック →「PowerShell で実行」）
2. 測りたい DC にチェックを入れる（起動時は全部チェック済み）
3. モード（-n 回数 / -t 連続）を選んで「Start selected」
4. 「Overlay」ボタンで小窓を表示。ドラッグで移動、マウスホイールで濃さ調整、右クリックで閉じる
5. 止めるときは「STOP ALL」。「Export CSV」で結果を保存できます

### 行の編集

- 名前・IP のセルを **ダブルクリック**すると、その場で書き換えられます（Enter で確定）
- 一番右の色セルを **ダブルクリック**すると、グラフの色を変えられます
- 「↑」「↓」で並び順を変更できます（オーバーレイの表示順にも反映されます）

## 注意

- **IP は変わることがあります。** うまく測れない DC は、実際の接続先に合わせて IP を編集してください。実際にゲームが通信している IP は、コマンドプロンプトの `netstat` でも調べられます
- 設定は `%APPDATA%\PingMonitor\settings.json` に保存されます。リセットしたいときはこのファイルを削除してください
- exe 版は、ウイルス対策ソフトに誤検知されることがあります（スクリプトを exe 化しているため）。心配な場合は、同梱の `PingMonitor.ps1`（ソース）の中身を確認できます

## 動作環境

Windows 10 / 11（Windows PowerShell 5.1 で動作確認）

## ライセンス

MIT License

---
---

# PingMonitor (English)

A lightweight tool to monitor ping quality to FF14 data centers (DCs), several at once.
It shows average ms, packet loss, and a trend graph in a small always-on-top overlay
that stays out of your way while gaming. No installation required. For Windows.

## Features

- Presets for the 4 FF14 DCs (Elemental / Gaia / Mana / Meteor). IPs can be added, edited, or removed
- Monitor multiple DCs at once, in count mode (-n) or continuous mode (-t)
- Live min / max / average / loss in the list
- Small always-on-top overlay: DC name, average ms, loss %, and a sparkline
- Color-coded quality verdict (see below)
- Export results to CSV (with timestamps) for later analysis
- Settings (IPs, names, colors, order, check state) are saved automatically and restored on next launch

## Quality verdict (the dot left of each name)

| Color | Verdict | Guideline |
|-------|---------|-----------|
| Cyan | EXCELLENT | 0% loss, max < 20ms |
| Green | GOOD | 0% loss, max < 100ms |
| Yellow | OK-ish | max 100–200ms |
| Red | BAD | any loss, or max > 200ms |

The verdict is based on the most recent 30 samples.

## How to use

1. Double-click `PingMonitor.bat` (or right-click `PingMonitor.ps1` → "Run with PowerShell")
2. Check the DCs you want to measure (all checked at startup)
3. Pick a mode (-n count / -t continuous) and click "Start selected"
4. Click "Overlay" for the small window. Drag to move, mouse wheel to change opacity, right-click to close
5. Click "STOP ALL" to stop. Use "Export CSV" to save results

### Editing rows

- **Double-click** a Name or IP cell to edit it in place (Enter to confirm)
- **Double-click** the color cell (far right) to change the graph color
- Use "↑" / "↓" to reorder (the overlay follows the same order)

## Notes

- **IPs can change.** If a DC won't measure correctly, edit its IP to the actual endpoint. You can find the IP your game is really talking to with `netstat` in Command Prompt
- Settings are stored in `%APPDATA%\PingMonitor\settings.json`. Delete that file to reset
- The exe build may be flagged by antivirus software (because it wraps a script). If concerned, you can review the included `PingMonitor.ps1` source

## Requirements

Windows 10 / 11 (tested on Windows PowerShell 5.1)

## License

MIT License
