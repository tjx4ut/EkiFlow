# EkiFlow - 駅訪問記録アプリ

全国9,048駅対応の駅訪問記録アプリです。

## 機能

- 🔍 **駅検索** - 全国の駅を検索
- 🚂 **ルート検索** - 出発駅→到着駅のルートを自動検索
- 📝 **記録** - 訪問した駅を「通過」「乗換」「行った」「最寄り」で記録
- 🗺️ **マップ** - 訪問した駅を地図上に表示
- 📊 **統計** - 都道府県別・ステータス別の統計

## Xcodeセットアップ手順

### 1. 新規プロジェクト作成

1. Xcodeを開く
2. 「Create New Project」を選択
3. 「iOS」→「App」を選択
4. 設定:
   - Product Name: `EkiFlow`
   - Interface: `SwiftUI`
   - Storage: `SwiftData`
   - Language: `Swift`
5. 保存場所を選んで「Create」

### 2. フォルダ構成を作成

プロジェクトナビゲータで右クリック → 「New Group」で以下を作成:

```
EkiFlow/
├── Models/
├── Views/
├── ViewModels/
├── Services/
└── Resources/
```

### 3. ファイルを追加

**重要**: 各フォルダに対応するファイルをドラッグ&ドロップ

| フォルダ | ファイル |
|---------|----------|
| Models/ | Station.swift, StationLog.swift, LogStatus.swift, Trip.swift |
| Views/ | ContentView.swift, HomeView.swift, SearchView.swift, StationDetailView.swift, LogListView.swift, TripInputView.swift, MapView.swift, StatsView.swift |
| ViewModels/ | StationViewModel.swift |
| Services/ | RouteSearchService.swift |
| Resources/ | japan_railway_data.json |
| (ルート) | EkiFlowApp.swift, Info.plist |

追加時の設定:
- ✅ Copy items if needed
- ✅ Create groups
- ✅ Add to targets: EkiFlow

### 4. 既存ファイルを置き換え

- `EkiFlowApp.swift` → 既存のを削除して新しいものを追加
- `ContentView.swift` → 既存のを削除して Views/ に新しいものを追加

### 5. ビルド設定

1. プロジェクト設定 → TARGETS → EkiFlow
2. General → Minimum Deployments: **iOS 17.0**
3. Signing & Capabilities → Team を設定

### 6. 実行

Command + R でシミュレーターで実行！

## 使い方

### 旅程を入力（メイン機能）

1. ホーム画面で「旅程を入力」をタップ
2. 「出発駅」を選択（検索して選ぶ）
3. 「到着駅」を選択
4. 「ルートを検索」をタップ
5. ルートが表示される:
   - 🟢 出発駅
   - 🟠 乗換駅
   - ⚪ 通過駅
   - 🔴 到着駅
6. 「この旅程を記録」で保存

### 個別に記録

1. 検索タブで駅を検索
2. 駅をタップして詳細画面へ
3. ステータスを選んで記録

## トラブルシューティング

### ビルドエラーが出る

1. Product → Clean Build Folder (Shift + Command + K)
2. Xcodeを再起動
3. もう一度ビルド

### 「japan_railway_data.json not found」

- `japan_railway_data.json` が Resources フォルダに入っているか確認
- ファイルを選択 → 右側の「Target Membership」で「EkiFlow」にチェック

## データについて

- 全国 **9,048駅** 対応
- 接続数: **9,562件**
- 乗換駅: **812駅**
- データソース: 国土数値情報（国土交通省）

## 開発期間

🎂 誕生日リリース計画:
- 12/22-23: MVP + 全国データ ✅
- 12/24-25: ルート検索 ✅
- 12/26-30: テスト・調整
- 12/31-1/1: App Store申請
- 1/8: 誕生日リリース！
