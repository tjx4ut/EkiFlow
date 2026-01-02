import SwiftUI
import SwiftData
import CoreLocation

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: StationViewModel
    @EnvironmentObject var tabResetManager: TabResetManager
    @State private var selectedStation: Station?
    @State private var searchMode: SearchMode = .station
    @State private var lineSearchResetId = UUID()  // LineSearchViewリセット用
    
    enum SearchMode: String, CaseIterable {
        case station = "駅"
        case line = "路線"
    }
    
    var body: some View {
        NavigationStack {
            // データロード中はローディング表示
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("駅データを読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("検索")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 0) {
                    // タブ切り替え
                    Picker("検索モード", selection: $searchMode) {
                        ForEach(SearchMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if searchMode == .station {
                        stationSearchView
                    } else {
                        LineSearchView()
                            .id(lineSearchResetId)
                    }
                }
                .navigationTitle("検索")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selectedStation) { station in
                    StationDetailView(station: station, showCloseButton: true)
                }
                .onChange(of: tabResetManager.searchResetTrigger) { oldValue, newValue in
                    resetToTop()
                }
            }
        }
    }
    
    private func resetToTop() {
        searchMode = .station
        viewModel.searchText = ""
        selectedStation = nil
        lineSearchResetId = UUID()  // LineSearchViewを再生成
    }
    
    private var stationSearchView: some View {
        List {
            // 検索中のインジケーター
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("検索中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // エイリアスで検索された場合のヒント
            if !viewModel.searchText.isEmpty {
                let matchedByAlias = viewModel.filteredStations.filter { station in
                    !station.name.localizedCaseInsensitiveContains(viewModel.searchText) &&
                    viewModel.getAliases(for: station.id).contains { alias in
                        alias.localizedCaseInsensitiveContains(viewModel.searchText)
                    }
                }

                if !matchedByAlias.isEmpty {
                    Section {
                        ForEach(matchedByAlias) { station in
                            StationRow(
                                station: station,
                                viewModel: viewModel,
                                matchedAlias: viewModel.getAliases(for: station.id).first {
                                    $0.localizedCaseInsensitiveContains(viewModel.searchText)
                                }
                            ) {
                                selectedStation = station
                            }
                        }
                    } header: {
                        Text("別名での検索結果")
                    }
                }

                // 駅名で直接マッチした駅
                let matchedByName = viewModel.filteredStations.filter { station in
                    station.name.localizedCaseInsensitiveContains(viewModel.searchText)
                }

                if !matchedByName.isEmpty {
                    Section {
                        ForEach(matchedByName) { station in
                            StationRow(
                                station: station,
                                viewModel: viewModel,
                                matchedAlias: nil
                            ) {
                                selectedStation = station
                            }
                        }
                    } header: {
                        if !matchedByAlias.isEmpty {
                            Text("駅名での検索結果")
                        }
                    }
                }
            } else {
                // 検索テキストが空の場合は近くの駅を7駅まで表示
                ForEach(viewModel.filteredStations.prefix(7)) { station in
                    StationRow(
                        station: station,
                        viewModel: viewModel,
                        matchedAlias: nil
                    ) {
                        selectedStation = station
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "駅名で検索")
    }
}

// MARK: - Line Search View

struct LineSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: StationViewModel
    
    @State private var lineSearchText = ""
    @State private var selectedLine: String?
    @State private var lineStations: [RailwayStation] = []
    @State private var selectedStationIds: Set<String> = []
    @State private var showingStatusPicker = false
    @State private var isSelectionMode = false  // 選択モード
    @State private var selectedStationForDetail: Station? = nil  // 駅詳細表示用
    @State private var isProcessing = false  // 一括登録中
    
    var filteredLines: [String] {
        if lineSearchText.isEmpty {
            return []
        }
        return RouteSearchService.shared.searchLines(query: lineSearchText)
    }
    
    // 近くの路線
    var nearbyLines: [String] {
        guard let location = LocationManager.shared.currentLocation else { return [] }
        return RouteSearchService.shared.getNearbyLines(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            limit: 5
        )
    }
    
    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            if selectedLine == nil {
                // 路線検索
                lineSearchList
            } else {
                // 路線の駅一覧
                lineStationsList
            }
        }
        .sheet(item: $selectedStationForDetail) { station in
            StationDetailView(station: station, showCloseButton: true)
        }
        
        // Loadingオーバーレイ
        if isProcessing {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("登録中...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(width: 120, height: 120)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        } // ZStack閉じ
    }
    
    private var lineSearchList: some View {
        List {
            if lineSearchText.isEmpty {
                // 近くの路線を表示
                if !nearbyLines.isEmpty {
                    Section("近くの路線") {
                        ForEach(nearbyLines, id: \.self) { line in
                            LineRowButton(line: line) {
                                selectLine(line)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("路線名を入力して検索")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if filteredLines.isEmpty {
                Section {
                    Text("該当する路線がありません")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("検索結果（\(filteredLines.count)件）") {
                    ForEach(filteredLines, id: \.self) { line in
                        LineRowButton(line: line) {
                            selectLine(line)
                        }
                    }
                }
            }
        }
        .searchable(text: $lineSearchText, prompt: "路線名で検索")
    }
    
    private var lineStationsList: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Button {
                    if isSelectionMode {
                        // 選択モード終了
                        isSelectionMode = false
                        selectedStationIds = []
                    } else {
                        // 路線一覧に戻る
                        selectedLine = nil
                        lineStations = []
                        selectedStationIds = []
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(isSelectionMode ? "キャンセル" : "戻る")
                    }
                }
                
                Spacer()
                
                Text(selectedLine ?? "")
                    .font(.headline)
                
                Spacer()
                
                if isSelectionMode {
                    // 選択モード: 完了ボタン
                    Button {
                        isSelectionMode = false
                        selectedStationIds.removeAll()
                    } label: {
                        Text("完了")
                            .font(.subheadline)
                    }
                } else {
                    // 閲覧モード: 選択ボタン
                    Button {
                        isSelectionMode = true
                    } label: {
                        Text("選択")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // 駅一覧
            List {
                Section("\(lineStations.count)駅") {
                    ForEach(lineStations) { station in
                        HStack {
                            // チェックボックス（選択モード時のみ）
                            if isSelectionMode {
                                Image(systemName: selectedStationIds.contains(station.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedStationIds.contains(station.id) ? .blue : .gray)
                            }

                            VStack(alignment: .leading) {
                                Text(station.name)
                                Text(station.prefecture)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // 現在のステータス
                            if let status = viewModel.getStrongestStatus(for: station.id) {
                                Text(status.emoji)
                            }

                            // 通常モードのみ矢印表示
                            if !isSelectionMode {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelectionMode {
                                if selectedStationIds.contains(station.id) {
                                    selectedStationIds.remove(station.id)
                                } else {
                                    selectedStationIds.insert(station.id)
                                }
                            } else {
                                // 通常モード：駅詳細に遷移
                                let stationModel = Station(
                                    id: station.id,
                                    name: station.name,
                                    prefecture: station.prefecture,
                                    latitude: station.latitude,
                                    longitude: station.longitude
                                )
                                selectedStationForDetail = stationModel
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // 一括変更ボタン（選択モードかつ選択がある場合）
                if isSelectionMode && !selectedStationIds.isEmpty {
                    VStack(spacing: 12) {
                        Text("\(selectedStationIds.count)駅を選択中")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(LogStatus.allCases, id: \.self) { status in
                                Button {
                                    applyStatusToSelected(status)
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(status.emoji)
                                            .font(.title2)
                                        Text(status.displayName)
                                            .font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(status.color.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .foregroundStyle(status.color)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
    }
    
    private func selectLine(_ line: String) {
        selectedLine = line
        lineStations = RouteSearchService.shared.getStationsForLine(line)
        selectedStationIds = []
        isSelectionMode = false  // 閲覧モードで開始
    }
    
    private func applyStatusToSelected(_ status: LogStatus) {
        isProcessing = true

        // 選択中の駅IDとデータをコピー
        let stationIdsToProcess = selectedStationIds
        let stationsData = lineStations.filter { stationIdsToProcess.contains($0.id) }
        let lineName = selectedLine ?? ""

        // UIを即座に更新（選択解除）
        selectedStationIds.removeAll()
        isSelectionMode = false

        // バックグラウンドでログを準備
        Task.detached(priority: .userInitiated) {
            // ログデータを準備（バックグラウンド）
            var logsToInsert: [(stationId: String, stationName: String, status: LogStatus, memo: String)] = []

            for station in stationsData {
                logsToInsert.append((
                    stationId: station.id,
                    stationName: station.name,
                    status: status,
                    memo: "路線一括登録: \(lineName)"
                ))
            }

            // メインスレッドでDB操作
            await MainActor.run {
                for logData in logsToInsert {
                    let log = StationLog(
                        stationId: logData.stationId,
                        stationName: logData.stationName,
                        status: logData.status,
                        memo: logData.memo
                    )
                    modelContext.insert(log)
                }

                do {
                    try modelContext.save()
                } catch {
                    print("Error saving: \(error)")
                }

                // キャッシュ無効化は少し遅延させる（UI応答性確保）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.invalidateCache()
                    isProcessing = false
                }
            }
        }
    }
}

struct StationRow: View {
    let station: Station
    let viewModel: StationViewModel
    let matchedAlias: String?
    let onTap: () -> Void
    
    // ひらがな読みを取得
    private var hiraganaReading: String? {
        let aliases = viewModel.getAliases(for: station.id)
        // ひらがなのみで構成されているaliasを探す
        return aliases.first { alias in
            alias.allSatisfy { char in
                char.isHiragana || char == "ー"
            }
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                // ひらがな読み
                if let reading = hiraganaReading {
                    Text(reading)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(station.name)
                                .font(.headline)
                            
                            // エイリアスでマッチした場合は表示（ひらがな以外）
                            if let alias = matchedAlias, alias != hiraganaReading {
                                Text("(\(alias))")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // 路線表示
                        if let stationData = viewModel.getStationData(byId: station.id) {
                            Text(stationData.lines.prefix(3).joined(separator: " / "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(station.prefecture)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let status = viewModel.getStrongestStatus(for: station.id) {
                        Text(status.emoji)
                            .font(.title2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Line Row Button（読み仮名付き）

struct LineRowButton: View {
    let line: String
    let onTap: () -> Void
    
    private var reading: String? {
        RouteSearchService.shared.getLineReading(line)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "tram.fill")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let reading = reading {
                        Text(reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(line)
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// ひらがな判定用の拡張
extension Character {
    var isHiragana: Bool {
        return ("\u{3040}"..."\u{309F}").contains(self)
    }
}

#Preview {
    SearchView()
        .environmentObject(StationViewModel())
        .environmentObject(TabResetManager())
}
