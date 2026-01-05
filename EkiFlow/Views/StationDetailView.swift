import SwiftUI
import SwiftData
import PhotosUI

struct StationDetailView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let station: Station
    var showCloseButton: Bool = false  // デフォルトは非表示（NavigationLink用）
    
    @State private var showingLogSheet = false
    @State private var selectedStatus: LogStatus = .visited
    @State private var memo = ""
    @State private var selectedVisitDate: Date = Date()
    @State private var hasVisitDate: Bool = true  // 訪問日を記録するかどうか
    @State private var editingLog: StationLog? = nil  // 編集中のログ
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var selectedLine: String? = nil  // 路線詳細表示用
    
    // この駅が最寄りかどうか
    private var isHome: Bool {
        viewModel.getHomeStations().contains { $0.id == station.id }
    }
    
    // この駅のログ履歴
    private var stationLogs: [StationLog] {
        viewModel.getLogs(for: station.id)
    }
    
    // 最強ステータス
    private var strongestStatus: LogStatus? {
        viewModel.getStrongestStatus(for: station.id)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 駅情報ヘッダー
                    headerSection
                    
                    // アクションボタン
                    actionButtons
                    
                    // 路線情報
                    linesSection
                    
                    // ログ履歴
                    logsSection
                }
                .padding()
            }
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                logInputSheet
            }
            .sheet(item: $selectedLine) { line in
                LineDetailView(lineName: line)
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            // ステータス表示
            if let status = strongestStatus {
                HStack {
                    Text(status.emoji)
                        .font(.largeTitle)
                    Text(status.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(status.color)
                }
            }
            
            // 都道府県
            Text(station.prefecture)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 最寄りバッジ
            if isHome {
                Label("最寄り駅", systemImage: "leaf.fill")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.486, green: 0.714, blue: 0.557).opacity(0.15))
                    .foregroundStyle(Color(red: 0.486, green: 0.714, blue: 0.557))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // ログ追加ボタン
            Button {
                // 新規追加モード：フォームをリセット
                editingLog = nil
                selectedStatus = .visited
                selectedVisitDate = Date()
                hasVisitDate = true
                memo = ""
                showingLogSheet = true
            } label: {
                Label("記録を追加", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // 最寄り追加/解除ボタン
            Button {
                toggleHome()
            } label: {
                Label(
                    isHome ? "最寄りから解除" : "最寄りに追加",
                    systemImage: isHome ? "leaf.slash" : "leaf.fill"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(isHome ? Color.red.opacity(0.1) : Color(red: 0.486, green: 0.714, blue: 0.557).opacity(0.15))
                .foregroundStyle(isHome ? .red : Color(red: 0.486, green: 0.714, blue: 0.557))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("路線")
                .font(.headline)
            
            if let stationData = viewModel.getStationData(byId: station.id) {
                FlowLayout(spacing: 8) {
                    ForEach(stationData.lines, id: \.self) { line in
                        Button {
                            selectedLine = line
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "tram.fill")
                                    .font(.caption2)
                                Text(line)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                        }
                    }
                }
            } else {
                Text("路線情報がありません")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("履歴")
                .font(.headline)
            
            if stationLogs.isEmpty {
                Text("まだ記録がありません")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(stationLogs) { log in
                    LogHistoryRow(log: log)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            startEditing(log: log)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var logInputSheet: some View {
        NavigationStack {
            Form {
                Section("ステータス") {
                    Picker("ステータス", selection: $selectedStatus) {
                        Text("🚶 行った").tag(LogStatus.visited)
                        Text("🔄 乗換").tag(LogStatus.transferred)
                        Text("🚃 通過").tag(LogStatus.passed)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("訪問日（任意）") {
                    Toggle("訪問日を記録する", isOn: $hasVisitDate)
                    
                    if hasVisitDate {
                        DatePicker(
                            "日付",
                            selection: $selectedVisitDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                    }
                }
                
                Section("メモ（任意）") {
                    TextField("メモを入力", text: $memo, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("写真（任意）") {
                    // 選択された画像のプレビュー
                    if let imageData = selectedImageData,
                       let uiImage = UIImage(data: imageData) {
                        HStack {
                            Spacer()
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                        }
                        
                        Button(role: .destructive) {
                            selectedImageData = nil
                            selectedPhotoItem = nil
                        } label: {
                            HStack {
                                Spacer()
                                Label("写真を削除", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                    
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images
                    ) {
                        HStack {
                            Spacer()
                            Label(selectedImageData == nil ? "写真を選択" : "写真を変更", systemImage: "photo")
                            Spacer()
                        }
                    }
                    .onChange(of: selectedPhotoItem) { oldValue, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        }
                    }
                }
                
                // 編集モードの場合、削除ボタンを表示
                if editingLog != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteLog()
                        } label: {
                            HStack {
                                Spacer()
                                Text("この記録を削除")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingLog == nil ? "記録を追加" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showingLogSheet = false
                        editingLog = nil
                        selectedImageData = nil
                        selectedPhotoItem = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveLog()
                        showingLogSheet = false
                        editingLog = nil
                        selectedImageData = nil
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
    
    // MARK: - Actions
    
    private func toggleHome() {
        if isHome {
            viewModel.removeHome(stationId: station.id)
        } else {
            viewModel.saveLog(station: station, status: .home, memo: "")
        }
    }
    
    private func saveLog() {
        let visitDate: Date? = hasVisitDate ? selectedVisitDate : nil
        
        if let log = editingLog {
            // 編集モード：既存のログを更新
            log.status = selectedStatus
            log.visitDate = visitDate
            log.memo = memo
            log.imageData = selectedImageData
            
            do {
                try modelContext.save()
            } catch {
                print("Error saving log: \(error)")
            }
        } else {
            // 新規モード：新しいログを作成
            let log = StationLog(
                stationId: station.id,
                stationName: station.name,
                status: selectedStatus,
                visitDate: visitDate,
                memo: memo,
                imageData: selectedImageData
            )
            modelContext.insert(log)
        }
        
        // リセット
        memo = ""
        selectedVisitDate = Date()
        hasVisitDate = true
        selectedStatus = .visited
        selectedImageData = nil
    }
    
    private func startEditing(log: StationLog) {
        editingLog = log
        selectedStatus = log.status
        if let visitDate = log.visitDate {
            selectedVisitDate = visitDate
            hasVisitDate = true
        } else {
            selectedVisitDate = Date()
            hasVisitDate = false
        }
        memo = log.memo
        selectedImageData = log.imageData
        showingLogSheet = true
    }
    
    private func deleteLog() {
        if let log = editingLog {
            modelContext.delete(log)
            do {
                try modelContext.save()
            } catch {
                print("Error deleting log: \(error)")
            }
        }
        showingLogSheet = false
        editingLog = nil
    }
}

// MARK: - Line Detail View（路線詳細画面）

struct LineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: StationViewModel
    
    let lineName: String
    
    @State private var lineStations: [RailwayStation] = []
    @State private var selectedStationIds: Set<String> = []
    @State private var isSelectionMode: Bool = false
    @State private var selectedStationForDetail: Station? = nil
    @State private var isProcessing: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
            VStack(spacing: 0) {
                // 駅一覧
                List {
                    Section("\(lineStations.count)駅") {
                        ForEach(lineStations) { station in
                            LineStationRow(
                                station: station,
                                isSelected: selectedStationIds.contains(station.id),
                                isSelectionMode: isSelectionMode,
                                status: viewModel.getStrongestStatus(for: station.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelectionMode {
                                    // 選択モード：チェックボックスのON/OFF
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
                
                // 一括変更ボタン（選択モードで選択がある場合）
                if isSelectionMode && !selectedStationIds.isEmpty {
                    VStack(spacing: 12) {
                        Text("\(selectedStationIds.count)駅を選択中")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(LogStatus.filterableCases, id: \.self) { status in
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
            .navigationTitle(lineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelectionMode ? "完了" : "選択") {
                        if isSelectionMode {
                            // 選択モード終了時に選択をクリア
                            selectedStationIds.removeAll()
                        }
                        isSelectionMode.toggle()
                    }
                }
            }
            .onAppear {
                lineStations = RouteSearchService.shared.getStationsForLine(lineName)
            }
            .sheet(item: $selectedStationForDetail) { station in
                StationDetailView(station: station, showCloseButton: true)
            }
        }
    }
    
    private func applyStatusToSelected(_ status: LogStatus) {
        isProcessing = true

        // UIの更新を先に行うため、少し遅延させて処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // グループ化用のtripIdを生成
            let tripId = UUID()

            // 路線順に並んだ駅を取得（選択された駅のみ）
            let orderedSelectedStations = lineStations.filter { selectedStationIds.contains($0.id) }

            for station in orderedSelectedStations {
                let log = StationLog(
                    stationId: station.id,
                    stationName: station.name,
                    status: status,
                    memo: "路線一括登録: \(lineName)",
                    tripId: tripId
                )
                modelContext.insert(log)
            }

            // 保存
            do {
                try modelContext.save()
                viewModel.invalidateCache()
            } catch {
                print("Error saving: \(error)")
            }

            // 選択解除して通常モードに戻る
            selectedStationIds.removeAll()
            isSelectionMode = false
            isProcessing = false
        }
    }
}

// MARK: - Line Station Row

struct LineStationRow: View {
    let station: RailwayStation
    let isSelected: Bool
    let isSelectionMode: Bool
    let status: LogStatus?
    
    var body: some View {
        HStack {
            // チェックボックス（選択モードのみ）
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .gray)
            }
            
            VStack(alignment: .leading) {
                Text(station.name)
                Text(station.prefecture)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 現在のステータス
            if let status = status {
                Text(status.emoji)
            }
            
            // 通常モードのみ矢印表示
            if !isSelectionMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected && isSelectionMode ? Color.blue.opacity(0.1) : Color.clear)
    }
}

// MARK: - Log History Row

struct LogHistoryRow: View {
    let log: StationLog
    
    var body: some View {
        HStack {
            Text(log.status.emoji)
            VStack(alignment: .leading) {
                Text(log.status.displayName)
                    .font(.subheadline)
                Text(log.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !log.memo.isEmpty {
                    Text(log.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // 写真・メモのインジケータ
            HStack(spacing: 4) {
                if log.imageData != nil {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Flow Layout（タグを折り返し表示）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - String Extension for sheet(item:)

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    StationDetailView(station: Station(
        id: "1130101",
        name: "東京",
        prefecture: "東京都",
        latitude: 35.681391,
        longitude: 139.766103
    ))
    .environmentObject(StationViewModel())
}
