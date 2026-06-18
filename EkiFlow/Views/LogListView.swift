import SwiftUI
import SwiftData
import PhotosUI

enum LogSortOption: String, CaseIterable {
    case visitedDateDesc = "訪問日（新しい順）"
    case visitedDateAsc = "訪問日（古い順）"
    case createdDateDesc = "記入日（新しい順）"
    case createdDateAsc = "記入日（古い順）"
}

enum LogViewMode: String, CaseIterable {
    case list = "リスト"
    case calendar = "カレンダー"
}

struct LogListView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @EnvironmentObject var tabResetManager: TabResetManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StationLog.timestamp, order: .reverse) private var logs: [StationLog]

    @State private var searchText = ""
    @State private var selectedFilter: LogStatus? = nil
    @State private var sortOption: LogSortOption = .visitedDateDesc
    @State private var viewMode: LogViewMode = .list
    @State private var selectedLogDate: Date? = nil
    @State private var scrollToTop: Bool = false

    // キャッシュ用
    @State private var cachedGroupedLogs: [LogGroup] = []
    @State private var isProcessing: Bool = true
    @State private var lastLogCount: Int = 0

    // 無限スクロール用
    private let pageSize = 20
    @State private var displayedGroupCount: Int = 20
    @State private var displayedFilteredCount: Int = 20
    
    var filteredLogs: [StationLog] {
        var result = logs
        
        if let filter = selectedFilter {
            result = result.filter { $0.status == filter }
        }
        
        if !searchText.isEmpty {
            let stationIds = viewModel.allStations
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .map { $0.id }
            result = result.filter { stationIds.contains($0.stationId) }
        }
        
        return result
    }
    
    // ソート済みログ（訪問日がnilのログは末尾に）
    var sortedLogs: [StationLog] {
        switch sortOption {
        case .visitedDateDesc:
            return filteredLogs.sorted { 
                guard let v1 = $0.visitDate else { return false }
                guard let v2 = $1.visitDate else { return true }
                return v1 > v2
            }
        case .visitedDateAsc:
            return filteredLogs.sorted { 
                guard let v1 = $0.visitDate else { return false }
                guard let v2 = $1.visitDate else { return true }
                return v1 < v2
            }
        case .createdDateDesc:
            return filteredLogs.sorted { $0.createdAt > $1.createdAt }
        case .createdDateAsc:
            return filteredLogs.sorted { $0.createdAt < $1.createdAt }
        }
    }
    
    // 訪問日があるログの日付セット（カレンダー表示用）
    var datesWithLogs: Set<DateComponents> {
        Set(filteredLogs.compactMap { log in
            guard let visitDate = log.visitDate else { return nil }
            return Calendar.current.dateComponents([.year, .month, .day], from: visitDate)
        })
    }
    
    // ログをグループ化（キャッシュを返す）
    var groupedLogs: [LogGroup] {
        cachedGroupedLogs
    }

    // グループ化を実行
    private func rebuildGroupedLogs() {
        isProcessing = true

        // メインスレッドでデータをコピーしてからグループ化
        let sorted = sortedLogs
        let currentLogCount = logs.count

        var groups: [LogGroup] = []
        var processedIds = Set<UUID>()

        for log in sorted {
            if processedIds.contains(log.id) { continue }

            if let journeyId = log.journeyId {
                let journeyLogs = sorted.filter { $0.journeyId == journeyId }
                processedIds.formUnion(journeyLogs.map { $0.id })
                groups.append(LogGroup(
                    id: journeyId,
                    logs: journeyLogs.sorted { $0.createdAt < $1.createdAt },
                    type: .journey
                ))
            } else if let tripId = log.tripId {
                let tripLogs = sorted.filter { $0.tripId == tripId }
                processedIds.formUnion(tripLogs.map { $0.id })
                groups.append(LogGroup(
                    id: tripId,
                    logs: tripLogs.sorted {
                        let v1 = $0.visitDate ?? $0.createdAt
                        let v2 = $1.visitDate ?? $1.createdAt
                        return v1 < v2
                    },
                    type: .trip
                ))
            } else {
                processedIds.insert(log.id)
                groups.append(LogGroup(id: log.id, logs: [log], type: .single))
            }
        }

        cachedGroupedLogs = groups
        lastLogCount = currentLogCount
        isProcessing = false
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 表示モード切替
                Picker("表示モード", selection: $viewMode) {
                    ForEach(LogViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if isProcessing && cachedGroupedLogs.isEmpty {
                    // 初回ローディング
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("ログを読み込み中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewMode == .list {
                    listView
                } else {
                    calendarView
                }
            }
            .navigationTitle("ログ")
            .searchable(text: $searchText, prompt: "駅名で検索")
            .toolbar {
                if viewMode == .list {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(LogSortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                    rebuildGroupedLogs()
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
            }
            .onChange(of: tabResetManager.logResetTrigger) { oldValue, newValue in
                resetToTop()
            }
            .onAppear {
                // 初回またはログ数が変わった場合に再計算
                if cachedGroupedLogs.isEmpty || logs.count != lastLogCount {
                    rebuildGroupedLogs()
                }
            }
            .onChange(of: logs.count) { _, _ in
                rebuildGroupedLogs()
                displayedGroupCount = pageSize
                displayedFilteredCount = pageSize
            }
            .onChange(of: selectedFilter) { _, _ in
                rebuildGroupedLogs()
                displayedFilteredCount = pageSize
            }
            .onChange(of: searchText) { _, _ in
                rebuildGroupedLogs()
                displayedGroupCount = pageSize
                displayedFilteredCount = pageSize
            }
        }
    }
    
    private func resetToTop() {
        searchText = ""
        selectedFilter = nil
        viewMode = .list
        selectedLogDate = nil
        scrollToTop = true
        // ページングをリセット
        displayedGroupCount = pageSize
        displayedFilteredCount = pageSize
    }
    
    // MARK: - List View

    // 表示用のグループ（ページング適用）
    private var displayedGroups: [LogGroup] {
        Array(groupedLogs.prefix(displayedGroupCount))
    }

    // 表示用のフィルタ済みログ（ページング適用）
    private var displayedFilteredLogs: [StationLog] {
        Array(sortedLogs.prefix(displayedFilteredCount))
    }

    private var hasMoreGroups: Bool {
        displayedGroupCount < groupedLogs.count
    }

    private var hasMoreFilteredLogs: Bool {
        displayedFilteredCount < sortedLogs.count
    }

    private func loadMoreGroups() {
        if hasMoreGroups {
            displayedGroupCount += pageSize
        }
    }

    private func loadMoreFilteredLogs() {
        if hasMoreFilteredLogs {
            displayedFilteredCount += pageSize
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            // フィルター
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "すべて", isSelected: selectedFilter == nil) {
                        selectedFilter = nil
                        displayedFilteredCount = pageSize
                    }
                    ForEach(LogStatus.filterableCases, id: \.self) { status in
                        FilterChip(title: "\(status.emoji) \(status.displayName)", isSelected: selectedFilter == status) {
                            selectedFilter = status
                            displayedFilteredCount = pageSize
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // ログ一覧
            List {
                if selectedFilter == nil {
                    ForEach(displayedGroups) { group in
                        LogGroupRow(group: group, viewModel: viewModel)
                            .onAppear {
                                // 最後の3件に到達したら追加読み込み
                                if let index = displayedGroups.firstIndex(where: { $0.id == group.id }),
                                   index >= displayedGroups.count - 3 {
                                    loadMoreGroups()
                                }
                            }
                    }
                    .onDelete(perform: deleteGroups)

                    // さらに読み込み中のインジケータ
                    if hasMoreGroups {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .onAppear {
                            loadMoreGroups()
                        }
                    }
                } else {
                    ForEach(displayedFilteredLogs) { log in
                        if let station = viewModel.getStation(byId: log.stationId) {
                            NavigationLink(destination: StationDetailView(station: station, showCloseButton: false)) {
                                SingleLogRow(log: log, stationName: station.name)
                            }
                            .onAppear {
                                // 最後の3件に到達したら追加読み込み
                                if let index = displayedFilteredLogs.firstIndex(where: { $0.id == log.id }),
                                   index >= displayedFilteredLogs.count - 3 {
                                    loadMoreFilteredLogs()
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteSingleLogs)

                    // さらに読み込み中のインジケータ
                    if hasMoreFilteredLogs {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .onAppear {
                            loadMoreFilteredLogs()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar View
    
    private var calendarView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    // 過去12ヶ月分のカレンダーを表示（上が昔、下が直近）
                    ForEach(getMonthsToShow(), id: \.self) { monthDate in
                        MonthCalendarView(
                            month: monthDate,
                            datesWithLogs: datesWithLogs,
                            logsGroupedByDate: getLogsGroupedByDate(),
                            onDateTap: { date in
                                selectedLogDate = date
                            }
                        )
                        .id(monthDate)
                    }
                }
                .padding(.vertical)
            }
            .onAppear {
                // 初期表示で今月にスクロール
                if let currentMonth = getMonthsToShow().last {
                    proxy.scrollTo(currentMonth, anchor: .bottom)
                }
            }
        }
        .sheet(item: $selectedLogDate) { date in
            DayDetailSheet(
                date: date,
                logs: getLogsForDate(date),
                viewModel: viewModel
            )
        }
    }
    
    private func getMonthsToShow() -> [Date] {
        let calendar = Calendar.current
        var months: [Date] = []
        let today = Date()
        
        // 過去12ヶ月から今月へ（上が昔、下が直近）
        for i in (0..<12).reversed() {
            if let monthDate = calendar.date(byAdding: .month, value: -i, to: today) {
                let components = calendar.dateComponents([.year, .month], from: monthDate)
                if let firstOfMonth = calendar.date(from: components) {
                    months.append(firstOfMonth)
                }
            }
        }
        return months
    }
    
    private func getLogsGroupedByDate() -> [Date: [LogGroup]] {
        var result: [Date: [LogGroup]] = [:]
        let calendar = Calendar.current
        
        for date in getSortedDatesWithLogs() {
            let startOfDay = calendar.startOfDay(for: date)
            result[startOfDay] = getLogsForDate(date)
        }
        return result
    }
    
    private func getSortedDatesWithLogs() -> [Date] {
        let dates = Set(filteredLogs.compactMap { log -> Date? in
            guard let visitDate = log.visitDate else { return nil }
            return Calendar.current.startOfDay(for: visitDate)
        })
        return dates.sorted(by: >)
    }
    
    private func getLogsForDate(_ date: Date) -> [LogGroup] {
        var groups: [LogGroup] = []
        var processedIds = Set<UUID>()
        let dateLogs = filteredLogs.filter { log in
            guard let visitDate = log.visitDate else { return false }
            return Calendar.current.isDate(visitDate, inSameDayAs: date)
        }
        
        for log in dateLogs {
            if processedIds.contains(log.id) { continue }
            
            if let journeyId = log.journeyId {
                let journeyLogs = dateLogs.filter { $0.journeyId == journeyId }
                processedIds.formUnion(journeyLogs.map { $0.id })
                groups.append(LogGroup(id: journeyId, logs: journeyLogs.sorted { $0.createdAt < $1.createdAt }, type: .journey))
            } else if let tripId = log.tripId {
                let tripLogs = dateLogs.filter { $0.tripId == tripId }
                processedIds.formUnion(tripLogs.map { $0.id })
                groups.append(LogGroup(id: tripId, logs: tripLogs.sorted { 
                    let v1 = $0.visitDate ?? $0.createdAt
                    let v2 = $1.visitDate ?? $1.createdAt
                    return v1 < v2
                }, type: .trip))
            } else {
                processedIds.insert(log.id)
                groups.append(LogGroup(id: log.id, logs: [log], type: .single))
            }
        }
        return groups
    }
    
    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets {
            let group = groupedLogs[index]
            for log in group.logs {
                modelContext.delete(log)
            }
        }
        try? modelContext.save()
    }
    
    private func deleteSingleLogs(at offsets: IndexSet) {
        for index in offsets {
            let log = sortedLogs[index]
            modelContext.delete(log)
        }
        try? modelContext.save()
    }
}

// MARK: - Log Group Model

struct LogGroup: Identifiable {
    let id: UUID
    let logs: [StationLog]
    let type: GroupType
    
    enum GroupType {
        case journey    // 旅（複数経路）
        case trip       // 経路追加
        case single     // 単発追加
    }
    
    var stationCount: Int { logs.count }
    
    // 経路数（journeyの場合）
    var routeCount: Int {
        Set(logs.compactMap { $0.tripId }).count
    }
    
    var displayEndDate: Date? {
        logs.first?.visitEndDate
    }

    var displayDate: Date? {
        logs.first?.visitDate
    }
    
    var createdDate: Date {
        logs.first?.createdAt ?? Date()
    }
    
    var status: LogStatus {
        logs.first?.status ?? .visited
    }
    
    var memo: String {
        logs.first?.memo ?? ""
    }

    var imageData: Data? {
        logs.first?.imageData
    }

    // 全ての画像を取得（グループ内の全ログから）
    var allImages: [Data] {
        logs.first?.allImages ?? []
    }

    // 写真があるかどうか
    var hasImages: Bool {
        !allImages.isEmpty
    }
}

// MARK: - Log Group Row

struct LogGroupRow: View {
    let group: LogGroup
    let viewModel: StationViewModel
    
    var body: some View {
        switch group.type {
        case .single:
            if let log = group.logs.first,
               let station = viewModel.getStation(byId: log.stationId) {
                NavigationLink(destination: StationDetailView(station: station, showCloseButton: false)) {
                    SingleLogRow(log: log, stationName: station.name)
                }
            }
        case .trip:
            NavigationLink(destination: TripLogDetailView(group: group, viewModel: viewModel)) {
                TripLogRow(group: group, viewModel: viewModel)
            }
        case .journey:
            NavigationLink(destination: JourneyLogDetailView(group: group, viewModel: viewModel)) {
                JourneyLogRow(group: group, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Single Log Row（単発）

struct SingleLogRow: View {
    let log: StationLog
    let stationName: String
    
    var body: some View {
        HStack {
            Text(log.status.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(stationName)
                    .font(.body)
                HStack {
                    Text(log.status.displayName)
                        .font(.caption)
                        .foregroundStyle(log.status.color)
                    if let visitDate = log.visitDate {
                        Text("•")
                            .foregroundStyle(.secondary)
                        if let endDate = log.visitEndDate {
                            Text("\(visitDate, style: .date)〜\(endDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(visitDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !log.memo.isEmpty {
                    Text(log.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trip Log Row（経路グループ）

struct TripLogRow: View {
    let group: LogGroup
    let viewModel: StationViewModel
    
    var body: some View {
        HStack {
            Text(group.status.emoji)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                // 駅名を → で繋げて表示
                Text(stationNamesText)
                    .font(.body)
                    .lineLimit(1)
                
                HStack {
                    Text("\(group.stationCount)駅")
                        .font(.caption)
                        .foregroundStyle(group.status.color)
                    if let displayDate = group.displayDate {
                        Text("•")
                            .foregroundStyle(.secondary)
                        if let endDate = group.displayEndDate {
                            Text("\(displayDate, style: .date)〜\(endDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(displayDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 写真アイコン
                    if group.hasImages {
                        HStack(spacing: 2) {
                            Image(systemName: "photo")
                            if group.allImages.count > 1 {
                                Text("\(group.allImages.count)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !group.memo.isEmpty {
                    Text(group.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var stationNamesText: String {
        let names = group.logs.compactMap { log -> String? in
            viewModel.getStation(byId: log.stationId)?.name ?? log.stationName
        }
        
        if names.count <= 3 {
            return names.joined(separator: " → ")
        } else {
            let first = names.first ?? ""
            let last = names.last ?? ""
            return "\(first) → ... → \(last)"
        }
    }
}

// MARK: - Trip Log Detail View（経路詳細）

struct TripLogDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let group: LogGroup
    let viewModel: StationViewModel

    @State private var showingEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var editDate: Date
    @State private var editEndDate: Date?
    @State private var editIsMultiDay: Bool
    @State private var editMemo: String
    @State private var editImagesData: [Data]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    private let maxPhotos = 10

    init(group: LogGroup, viewModel: StationViewModel) {
        self.group = group
        self.viewModel = viewModel
        _editDate = State(initialValue: group.displayDate ?? Date())
        _editEndDate = State(initialValue: group.displayEndDate)
        _editIsMultiDay = State(initialValue: group.displayEndDate != nil)
        _editMemo = State(initialValue: group.memo)
        _editImagesData = State(initialValue: group.allImages)
    }

    var body: some View {
        List {
            // 写真セクション（複数枚対応）
            if !group.allImages.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(group.allImages.enumerated()), id: \.offset) { index, imageData in
                                if let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 200, height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            
            Section {
                HStack {
                    Text("訪問日")
                    Spacer()
                    if let displayDate = group.displayDate {
                        if let endDate = group.displayEndDate {
                            Text("\(displayDate, style: .date)〜\(endDate, style: .date)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(displayDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("未設定")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("記入日")
                    Spacer()
                    Text(group.createdDate, style: .date)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("ステータス")
                    Spacer()
                    Text("\(group.status.emoji) \(group.status.displayName)")
                }
                HStack {
                    Text("駅数")
                    Spacer()
                    Text("\(group.stationCount)駅")
                        .foregroundStyle(.secondary)
                }
                if !group.memo.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("メモ")
                        Text(group.memo)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("経路") {
                ForEach(group.logs, id: \.id) { log in
                    if let station = viewModel.getStation(byId: log.stationId) {
                        NavigationLink(destination: StationDetailView(station: station, showCloseButton: false)) {
                            HStack {
                                Text(log.status.emoji)
                                Text(station.name)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("経路詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    editDate = group.displayDate ?? Date()
                    editEndDate = group.displayEndDate
                    editIsMultiDay = group.displayEndDate != nil
                    editMemo = group.memo
                    editImagesData = group.allImages
                    selectedPhotoItems = []
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            editSheet
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("訪問日") {
                    Toggle("複数日選択", isOn: $editIsMultiDay)
                        .onChange(of: editIsMultiDay) { _, newValue in
                            if !newValue {
                                editEndDate = nil
                            }
                        }

                    if editIsMultiDay {
                        RangeCalendarView(startDate: $editDate, endDate: $editEndDate)
                    } else {
                        DatePicker(
                            "訪問日",
                            selection: $editDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                    }
                }

                Section("メモ") {
                    TextField("メモを入力", text: $editMemo, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("写真（\(editImagesData.count)/\(maxPhotos)枚）") {
                    // 既存の写真を表示
                    if !editImagesData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(editImagesData.enumerated()), id: \.offset) { index, imageData in
                                    if let uiImage = UIImage(data: imageData) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                            Button {
                                                editImagesData.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .red)
                                                    .font(.title3)
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // 写真追加ボタン
                    if editImagesData.count < maxPhotos {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: maxPhotos - editImagesData.count,
                            matching: .images
                        ) {
                            HStack {
                                Spacer()
                                Label("写真を追加", systemImage: "photo.badge.plus")
                                Spacer()
                            }
                        }
                        .onChange(of: selectedPhotoItems) { oldValue, newValue in
                            Task {
                                for item in newValue {
                                    if let data = try? await item.loadTransferable(type: Data.self) {
                                        if editImagesData.count < maxPhotos {
                                            editImagesData.append(data)
                                        }
                                    }
                                }
                                selectedPhotoItems = []
                            }
                        }
                    } else {
                        Text("写真は最大\(maxPhotos)枚までです")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 削除セクション
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("この経路を削除", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("経路を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showingEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                        showingEditSheet = false
                    }
                }
            }
            .alert("経路を削除", isPresented: $showDeleteConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    deleteGroup()
                }
            } message: {
                Text("この経路の記録（\(group.stationCount)駅分）を削除しますか？\nこの操作は取り消せません。")
            }
        }
        .presentationDetents([.large])
    }
    
    private func deleteGroup() {
        for log in group.logs {
            modelContext.delete(log)
        }
        try? modelContext.save()
        showingEditSheet = false
        dismiss()
    }
    
    private func saveChanges() {
        // グループ内の全ログを更新
        for (index, log) in group.logs.enumerated() {
            log.visitDate = editDate
            log.visitEndDate = editIsMultiDay ? editEndDate : nil
            if index == 0 {
                log.memo = editMemo
                log.imagesData = editImagesData
                log.imageData = nil  // 新形式に移行
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Journey Log Row（旅グループ）

struct JourneyLogRow: View {
    let group: LogGroup
    let viewModel: StationViewModel
    
    var body: some View {
        HStack {
            Text("🗺️")
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(journeyTitle)
                    .font(.body)
                    .lineLimit(1)
                
                HStack {
                    Text("\(group.routeCount)経路")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(group.stationCount)駅")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let displayDate = group.displayDate {
                        Text("•")
                            .foregroundStyle(.secondary)
                        if let endDate = group.displayEndDate {
                            Text("\(displayDate, style: .date)〜\(endDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(displayDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if group.hasImages {
                        HStack(spacing: 2) {
                            Image(systemName: "photo")
                            if group.allImages.count > 1 {
                                Text("\(group.allImages.count)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !group.memo.isEmpty {
                    Text(group.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var journeyTitle: String {
        // 各経路の出発・到着駅を取得
        let tripIds = Array(Set(group.logs.compactMap { $0.tripId }))
        var stationNames: [String] = []
        
        for tripId in tripIds {
            let tripLogs = group.logs.filter { $0.tripId == tripId }
            if let first = tripLogs.first, let last = tripLogs.last {
                let fromName = viewModel.getStation(byId: first.stationId)?.name ?? first.stationName ?? ""
                let toName = viewModel.getStation(byId: last.stationId)?.name ?? last.stationName ?? ""
                if !fromName.isEmpty && !toName.isEmpty && fromName != toName {
                    stationNames.append("\(fromName)→\(toName)")
                } else if !fromName.isEmpty {
                    stationNames.append(fromName)
                }
            }
        }
        
        if stationNames.isEmpty {
            return "旅の記録"
        } else if stationNames.count <= 2 {
            return stationNames.joined(separator: " / ")
        } else {
            return "\(stationNames[0]) / \(stationNames[1]) / ..."
        }
    }
}

// MARK: - Journey Log Detail View（旅詳細）

struct JourneyLogDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let group: LogGroup
    let viewModel: StationViewModel

    @State private var showingEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var editDate: Date
    @State private var editEndDate: Date?
    @State private var editIsMultiDay: Bool
    @State private var editMemo: String
    @State private var editImagesData: [Data]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    private let maxPhotos = 10

    init(group: LogGroup, viewModel: StationViewModel) {
        self.group = group
        self.viewModel = viewModel
        _editDate = State(initialValue: group.displayDate ?? Date())
        _editEndDate = State(initialValue: group.displayEndDate)
        _editIsMultiDay = State(initialValue: group.displayEndDate != nil)
        _editMemo = State(initialValue: group.memo)
        _editImagesData = State(initialValue: group.allImages)
    }

    // 経路ごとにグループ化
    var routeGroups: [[StationLog]] {
        let tripIds = Array(Set(group.logs.compactMap { $0.tripId }))
        return tripIds.map { tripId in
            group.logs.filter { $0.tripId == tripId }.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        List {
            // 写真セクション（複数枚対応）
            if !group.allImages.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(group.allImages.enumerated()), id: \.offset) { index, imageData in
                                if let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 200, height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            
            Section {
                HStack {
                    Text("訪問日")
                    Spacer()
                    if let displayDate = group.displayDate {
                        if let endDate = group.displayEndDate {
                            Text("\(displayDate, style: .date)〜\(endDate, style: .date)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(displayDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("未設定")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("記入日")
                    Spacer()
                    Text(group.createdDate, style: .date)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("経路数")
                    Spacer()
                    Text("\(group.routeCount)経路")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("駅数")
                    Spacer()
                    Text("\(group.stationCount)駅")
                        .foregroundStyle(.secondary)
                }
                if !group.memo.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("メモ")
                        Text(group.memo)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // 各経路
            ForEach(Array(routeGroups.enumerated()), id: \.offset) { index, routeLogs in
                Section("経路 \(index + 1)") {
                    ForEach(routeLogs, id: \.id) { log in
                        if let station = viewModel.getStation(byId: log.stationId) {
                            NavigationLink(destination: StationDetailView(station: station, showCloseButton: false)) {
                                HStack {
                                    Text(log.status.emoji)
                                    Text(station.name)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("旅の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    editDate = group.displayDate ?? Date()
                    editEndDate = group.displayEndDate
                    editIsMultiDay = group.displayEndDate != nil
                    editMemo = group.memo
                    editImagesData = group.allImages
                    selectedPhotoItems = []
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            editSheet
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("訪問日") {
                    Toggle("複数日選択", isOn: $editIsMultiDay)
                        .onChange(of: editIsMultiDay) { _, newValue in
                            if !newValue {
                                editEndDate = nil
                            }
                        }

                    if editIsMultiDay {
                        RangeCalendarView(startDate: $editDate, endDate: $editEndDate)
                    } else {
                        DatePicker(
                            "訪問日",
                            selection: $editDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                    }
                }

                Section("メモ") {
                    TextField("メモを入力", text: $editMemo, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("写真（\(editImagesData.count)/\(maxPhotos)枚）") {
                    // 既存の写真を表示
                    if !editImagesData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(editImagesData.enumerated()), id: \.offset) { index, imageData in
                                    if let uiImage = UIImage(data: imageData) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                            Button {
                                                editImagesData.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .red)
                                                    .font(.title3)
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // 写真追加ボタン
                    if editImagesData.count < maxPhotos {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: maxPhotos - editImagesData.count,
                            matching: .images
                        ) {
                            HStack {
                                Spacer()
                                Label("写真を追加", systemImage: "photo.badge.plus")
                                Spacer()
                            }
                        }
                        .onChange(of: selectedPhotoItems) { oldValue, newValue in
                            Task {
                                for item in newValue {
                                    if let data = try? await item.loadTransferable(type: Data.self) {
                                        if editImagesData.count < maxPhotos {
                                            editImagesData.append(data)
                                        }
                                    }
                                }
                                selectedPhotoItems = []
                            }
                        }
                    } else {
                        Text("写真は最大\(maxPhotos)枚までです")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 削除セクション
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("この旅を削除", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("旅を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showingEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                        showingEditSheet = false
                    }
                }
            }
            .alert("旅を削除", isPresented: $showDeleteConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    deleteGroup()
                }
            } message: {
                Text("この旅の記録（\(group.routeCount)経路・\(group.stationCount)駅分）を削除しますか？\nこの操作は取り消せません。")
            }
        }
        .presentationDetents([.large])
    }
    
    private func deleteGroup() {
        for log in group.logs {
            modelContext.delete(log)
        }
        try? modelContext.save()
        showingEditSheet = false
        dismiss()
    }
    
    private func saveChanges() {
        for (index, log) in group.logs.enumerated() {
            log.visitDate = editDate
            log.visitEndDate = editIsMultiDay ? editEndDate : nil
            if index == 0 {
                log.memo = editMemo
                log.imagesData = editImagesData
                log.imageData = nil  // 新形式に移行
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Month Calendar View (BeReal Style)

struct MonthCalendarView: View {
    let month: Date
    let datesWithLogs: Set<DateComponents>
    let logsGroupedByDate: [Date: [LogGroup]]
    let onDateTap: (Date) -> Void
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: month)
    }
    
    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingEmpty = firstWeekday - 1
        
        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func hasLog(on date: Date) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return datesWithLogs.contains(components)
    }
    
    private func getImageData(for date: Date) -> Data? {
        let startOfDay = calendar.startOfDay(for: date)
        guard let groups = logsGroupedByDate[startOfDay] else { return nil }
        // 最初に見つかった画像を返す
        for group in groups {
            if let imageData = group.imageData {
                return imageData
            }
        }
        return nil
    }
    
    private func getStationCount(for date: Date) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        guard let groups = logsGroupedByDate[startOfDay] else { return 0 }
        return groups.reduce(0) { $0 + $1.stationCount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 月タイトル
            Text(monthTitle)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // 曜日ヘッダー
            HStack(spacing: 4) {
                ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            
            // カレンダーグリッド
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { index, date in
                    if let date = date {
                        DayCell(
                            date: date,
                            hasLog: hasLog(on: date),
                            imageData: getImageData(for: date),
                            stationCount: getStationCount(for: date),
                            isToday: calendar.isDateInToday(date),
                            isFuture: date > Date(),
                            onTap: { onDateTap(date) }
                        )
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let hasLog: Bool
    let imageData: Data?
    let stationCount: Int
    let isToday: Bool
    let isFuture: Bool
    let onTap: () -> Void
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .aspectRatio(1, contentMode: .fit)
                
                // 画像がある場合はサムネイル表示
                if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // 日付と駅数
                VStack(spacing: 2) {
                    Text("\(dayNumber)")
                        .font(.system(size: 14, weight: isToday ? .bold : .medium))
                        .foregroundStyle(textColor)
                    
                    if hasLog && stationCount > 0 {
                        Text("\(stationCount)駅")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(hasLog ? .white : .secondary)
                    }
                }
                .shadow(color: imageData != nil ? .black.opacity(0.5) : .clear, radius: 2)
                
                // 枠線
                if hasLog {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isToday ? Color.blue : Color.orange, lineWidth: 2)
                }
            }
        }
        .disabled(isFuture || !hasLog)
        .opacity(isFuture ? 0.3 : 1)
    }
    
    private var backgroundColor: Color {
        if imageData != nil {
            return .clear
        } else if hasLog {
            return Color.orange.opacity(0.2)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var textColor: Color {
        if imageData != nil {
            return .white
        } else if isToday {
            return .blue
        } else if isFuture {
            return .secondary
        } else {
            return hasLog ? .orange : .primary
        }
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let logs: [LogGroup]
    let viewModel: StationViewModel
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    Text("この日の記録はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { group in
                        LogGroupRow(group: group, viewModel: viewModel)
                    }
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Date Extension for Identifiable

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { self.timeIntervalSince1970 }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    LogListView()
        .environmentObject(StationViewModel())
        .environmentObject(TabResetManager())
        .modelContainer(for: [Station.self, StationLog.self])
}
