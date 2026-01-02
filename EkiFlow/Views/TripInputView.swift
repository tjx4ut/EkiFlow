import SwiftUI
import SwiftData
import CoreLocation
import PhotosUI

struct TripInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDeparture: RailwayStation?
    @State private var selectedArrival: RailwayStation?
    @State private var viaStations: [RailwayStation] = []  // 経由駅（複数可）
    @State private var routes: [[RouteStop]] = []  // 複数ルート
    @State private var selectedRouteIndex: Int = 0
    @State private var isSearchingRoute = false
    @State private var showingDepartureSearch = false
    @State private var showingArrivalSearch = false
    @State private var showingViaSearch = false
    @State private var memo = ""
    @State private var tripDate = Date()  // 訪問日
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []

    private let maxPhotos = 10

    // 複数経路用
    @State private var savedRoutes: [[RouteStop]] = []  // 保存済みの経路リスト
    
    // ルート検索オプション
    @State private var useShinkansen = true    // 新幹線を使う
    @State private var useLimitedExpress = true  // 特急を使う
    @State private var showPassStations = false  // 通過駅を表示
    
    var body: some View {
        NavigationStack {
            Form {
                // 追加済みの経路
                if !savedRoutes.isEmpty {
                    savedRoutesSection
                }
                
                stationSelectionSection
                searchOptionsSection
                
                if !routes.isEmpty {
                    routeSelectionSection
                    selectedRouteSection
                    addRouteButton
                }
                
                // 保存セクション（経路が1つ以上あれば表示）
                if !savedRoutes.isEmpty || !routes.isEmpty {
                    memoSection
                    saveSection
                }
            }
            .navigationTitle("旅を入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingDepartureSearch) {
                RouteStationSearchView(
                    title: "出発駅を選択",
                    selectedStation: $selectedDeparture
                )
            }
            .sheet(isPresented: $showingArrivalSearch) {
                RouteStationSearchView(
                    title: "到着駅を選択",
                    selectedStation: $selectedArrival
                )
            }
            .sheet(isPresented: $showingViaSearch) {
                ViaStationSearchView(
                    viaStations: $viaStations
                )
            }
            .alert("エラー", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: selectedDeparture?.id) { _, _ in routes = [] }
            .onChange(of: selectedArrival?.id) { _, _ in routes = [] }
            .onChange(of: viaStations.count) { _, _ in routes = [] }
        }
    }
    
    // MARK: - Sections
    
    private var stationSelectionSection: some View {
        Section("駅を選択") {
            // 出発駅
            Button {
                showingDepartureSearch = true
            } label: {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.green)
                    Text("出発駅")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let departure = selectedDeparture {
                        Text(departure.name)
                            .foregroundStyle(.primary)
                    } else {
                        Text("選択してください")
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            // 経由駅リスト
            ForEach(Array(viaStations.enumerated()), id: \.offset) { index, station in
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(.orange)
                    Text(station.name)
                    Spacer()
                    Button {
                        viaStations.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .onMove { from, to in
                viaStations.move(fromOffsets: from, toOffset: to)
            }
            
            // 経由駅追加ボタン + 入れ替えボタン
            HStack {
                Button {
                    showingViaSearch = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("経由駅を追加")
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                if selectedDeparture != nil || selectedArrival != nil {
                    Button {
                        let temp = selectedDeparture
                        selectedDeparture = selectedArrival
                        selectedArrival = temp
                        routes = []
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // 到着駅
            Button {
                showingArrivalSearch = true
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.red)
                    Text("到着駅")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let arrival = selectedArrival {
                        Text(arrival.name)
                            .foregroundStyle(.primary)
                    } else {
                        Text("選択してください")
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            // ルート検索ボタン
            if selectedDeparture != nil && selectedArrival != nil {
                Button {
                    searchRoutes()
                } label: {
                    HStack {
                        Spacer()
                        if isSearchingRoute {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Image(systemName: "magnifyingglass")
                        Text("ルートを検索")
                        Spacer()
                    }
                }
                .disabled(isSearchingRoute)
            }
        }
    }
    
    
    private var searchOptionsSection: some View {
        Section("検索オプション") {
            Toggle(isOn: $useShinkansen) {
                Label("新幹線を使う", systemImage: "tram.fill")
            }
            .onChange(of: useShinkansen) { _, _ in
                if selectedDeparture != nil && selectedArrival != nil {
                    searchRoutes()
                }
            }
            
            Toggle(isOn: $useLimitedExpress) {
                Label("特急を使う", systemImage: "train.side.front.car")
            }
            .onChange(of: useLimitedExpress) { _, _ in
                if selectedDeparture != nil && selectedArrival != nil {
                    searchRoutes()
                }
            }
        }
    }
    
    private var routeSelectionSection: some View {
        Section("ルート選択（\(routes.count)件）") {
            ForEach(0..<routes.count, id: \.self) { index in
                Button {
                    selectedRouteIndex = index
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ルート \(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            let duration = RouteSearchService.shared.calculateRouteDuration(route: routes[index])
                            let transfers = getTransferCount(route: routes[index])
                            let hasWalk = routeHasWalk(route: routes[index])
                            
                            HStack(spacing: 4) {
                                Text("約\(duration)分・\(routes[index].count)駅・\(transfers)回乗換")
                                if hasWalk {
                                    Label("徒歩", systemImage: "figure.walk")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            Text(getRoutePreview(route: routes[index]))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if selectedRouteIndex == index {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var selectedRouteSection: some View {
        let passCount = currentRoute.filter { $0.status == .pass }.count
        
        return Section("選択中のルート（\(currentRoute.count)駅）") {
            ForEach(0..<currentRoute.count, id: \.self) { index in
                let stop = currentRoute[index]
                
                if stop.status == .pass {
                    // 通過駅：収納時は非表示
                    if showPassStations {
                        RouteStopRow(stop: stop) { newLine in
                            updateLine(at: index, newLine: newLine)
                        }
                        .opacity(0.6)
                    }
                } else {
                    // 主要駅は常に表示
                    RouteStopRow(stop: stop) { newLine in
                        updateLine(at: index, newLine: newLine)
                    }
                    
                    // 次の通過駅群の前に「通過駅を表示」ボタンを配置
                    if !showPassStations && hasPassStationsAfter(index: index) {
                        let passCountInSegment = countPassStationsAfter(index: index)
                        Button {
                            withAnimation {
                                showPassStations = true
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "ellipsis")
                                Text("\(passCountInSegment)駅を表示")
                                    .font(.caption)
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 通過駅を隠すボタン
            if showPassStations && passCount > 0 {
                Button {
                    withAnimation {
                        showPassStations = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.up")
                        Text("通過駅を隠す")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func updateLine(at index: Int, newLine: String) {
        guard selectedRouteIndex < routes.count else { return }
        routes[selectedRouteIndex][index].line = newLine
    }
    
    private func hasPassStationsAfter(index: Int) -> Bool {
        guard index + 1 < currentRoute.count else { return false }
        return currentRoute[index + 1].status == .pass
    }
    
    private func countPassStationsAfter(index: Int) -> Int {
        var count = 0
        for i in (index + 1)..<currentRoute.count {
            if currentRoute[i].status == .pass {
                count += 1
            } else {
                break
            }
        }
        return count
    }
    
    // MARK: - 追加済みの経路セクション
    
    private var savedRoutesSection: some View {
        Section("追加済みの経路（\(savedRoutes.count)）") {
            ForEach(Array(savedRoutes.enumerated()), id: \.offset) { index, route in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // 経路プレビュー
                        Text(getRoutePreviewText(route))
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        // 駅数と路線
                        Text("\(route.count)駅")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // 削除ボタン
                    Button {
                        savedRoutes.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func getRoutePreviewText(_ route: [RouteStop]) -> String {
        let keyStops = route.filter { $0.status == .departure || $0.status == .transfer || $0.status == .arrival }
        if keyStops.count <= 3 {
            return keyStops.map { $0.stationName }.joined(separator: " → ")
        } else {
            let first = keyStops.first?.stationName ?? ""
            let last = keyStops.last?.stationName ?? ""
            return "\(first) → ... → \(last)"
        }
    }
    
    // MARK: - 経路追加ボタン
    
    private var addRouteButton: some View {
        Section {
            Button {
                addCurrentRoute()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                    Text("この経路を追加")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .listRowBackground(Color.blue)
            .foregroundStyle(.white)
        }
    }
    
    private func addCurrentRoute() {
        // 現在の経路を保存済みリストに追加
        savedRoutes.append(currentRoute)
        
        // 検索結果をリセット
        routes = []
        selectedRouteIndex = 0
        
        // 次の経路の出発駅を現在の到着駅に設定
        if let arrival = selectedArrival {
            selectedDeparture = arrival
            selectedArrival = nil
        }
        viaStations = []
    }
    
    private var memoSection: some View {
        Section("訪問日・メモ・写真（\(selectedImagesData.count)/\(maxPhotos)枚）") {
            DatePicker(
                "訪問日",
                selection: $tripDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)

            TextField("旅行の思い出など（任意）", text: $memo, axis: .vertical)
                .lineLimit(3...6)

            // 写真表示
            if !selectedImagesData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedImagesData.enumerated()), id: \.offset) { index, imageData in
                            if let uiImage = UIImage(data: imageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button {
                                        selectedImagesData.remove(at: index)
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
            if selectedImagesData.count < maxPhotos {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: maxPhotos - selectedImagesData.count,
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
                                if selectedImagesData.count < maxPhotos {
                                    selectedImagesData.append(data)
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
    }
    
    private var saveSection: some View {
        Section {
            Button {
                saveTrip()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                    Text("この旅を記録")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .listRowBackground(Color.green)
            .foregroundStyle(.white)
        }
    }
    
    private var currentRoute: [RouteStop] {
        guard selectedRouteIndex < routes.count else { return [] }
        return routes[selectedRouteIndex]
    }
    
    // MARK: - Functions
    
    private func searchRoutes() {
        guard let departure = selectedDeparture,
              let arrival = selectedArrival else { return }
        
        isSearchingRoute = true
        routes = []
        
        // フィルター設定をキャプチャ
        let shinkansen = useShinkansen
        let limitedExpress = useLimitedExpress
        
        DispatchQueue.global(qos: .userInitiated).async {
            let foundRoutes: [[RouteStop]]
            
            if viaStations.isEmpty {
                // 経由駅なし：複数ルート検索
                foundRoutes = RouteSearchService.shared.findMultipleRoutes(
                    fromId: departure.id,
                    toId: arrival.id,
                    maxRoutes: 5,
                    useShinkansen: shinkansen,
                    useLimitedExpress: limitedExpress
                )
            } else {
                // 経由駅あり：経由駅を通るルートを検索
                foundRoutes = RouteSearchService.shared.findRouteVia(
                    fromId: departure.id,
                    toId: arrival.id,
                    viaIds: viaStations.map { $0.id }
                )
            }
            
            DispatchQueue.main.async {
                isSearchingRoute = false
                if !foundRoutes.isEmpty {
                    routes = foundRoutes
                    selectedRouteIndex = 0
                } else {
                    errorMessage = "ルートが見つかりませんでした。\n別の駅を選択してください。"
                    showingError = true
                }
            }
        }
    }
    
    private func getTransferCount(route: [RouteStop]) -> Int {
        return route.filter { $0.status == .transfer }.count
    }
    
    private func routeHasWalk(route: [RouteStop]) -> Bool {
        return route.contains { $0.line == "徒歩" }
    }
    
    private func getRoutePreview(route: [RouteStop]) -> String {
        let keyStops = route.filter { $0.status == .departure || $0.status == .transfer || $0.status == .arrival }
        return keyStops.map { $0.stationName }.joined(separator: " → ")
    }
    
    private func saveTrip() {
        let journeyId = UUID()  // 旅全体のID
        
        // 保存する全ての経路を収集
        var allRoutes = savedRoutes
        if !currentRoute.isEmpty {
            allRoutes.append(currentRoute)
        }
        
        var isFirstLog = true
        
        for route in allRoutes {
            let tripId = UUID()  // 各経路のID
            
            for (index, stop) in route.enumerated() {
                let station = findOrCreateStation(for: stop)
                
                let status: LogStatus
                switch stop.status {
                case .departure, .arrival:
                    status = .visited
                case .transfer:
                    status = .transferred
                case .pass:
                    status = .passed
                }
                
                let log = StationLog(
                    stationId: station.id,
                    stationName: stop.stationName,
                    status: status,
                    visitDate: tripDate,
                    memo: isFirstLog ? memo : "",
                    imagesData: isFirstLog ? selectedImagesData : [],
                    tripId: tripId,
                    journeyId: journeyId,
                    autoGenerated: index != 0 && index != route.count - 1
                )
                modelContext.insert(log)
                isFirstLog = false
            }
        }
        
        try? modelContext.save()
        dismiss()
    }
    
    private func findOrCreateStation(for stop: RouteStop) -> Station {
        let descriptor = FetchDescriptor<Station>()
        if let allStations = try? modelContext.fetch(descriptor) {
            if let existing = allStations.first(where: { $0.id == stop.stationId }) {
                return existing
            }
        }
        
        let newStation = Station(
            id: stop.stationId,
            name: stop.stationName,
            prefecture: stop.prefecture,
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        modelContext.insert(newStation)
        return newStation
    }
}

// MARK: - Route Stop Row

struct RouteStopRow: View {
    let stop: RouteStop
    var onLineSelected: ((String) -> Void)? = nil
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.stationName)
                    .font(.body)
                
                // 路線表示（代替路線がある場合は選択可能）
                if let line = stop.line {
                    if stop.alternativeLines.count > 1, let onLineSelected = onLineSelected {
                        // 複数路線から選択可能
                        Menu {
                            ForEach(stop.alternativeLines, id: \.self) { altLine in
                                Button {
                                    onLineSelected(altLine)
                                } label: {
                                    HStack {
                                        if altLine == "徒歩" {
                                            Label(altLine, systemImage: "figure.walk")
                                        } else {
                                            Text(altLine)
                                        }
                                        if altLine == line {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if line == "徒歩" {
                                    Label("徒歩で移動", systemImage: "figure.walk")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    } else {
                        // 単一路線（選択不可）
                        if line == "徒歩" {
                            Label("徒歩で移動", systemImage: "figure.walk")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            Text(stop.status.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
    
    private var iconName: String {
        switch stop.status {
        case .departure: return "arrow.up.circle.fill"
        case .arrival: return "arrow.down.circle.fill"
        case .transfer: return "arrow.triangle.swap"
        case .pass: return "circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch stop.status {
        case .departure: return .green
        case .arrival: return .red
        case .transfer: return .orange
        case .pass: return .gray
        }
    }
}

// MARK: - Route Station Search View

struct RouteStationSearchView: View {
    let title: String
    @Binding var selectedStation: RailwayStation?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var searchQuery = ""
    @State private var searchResults: [RailwayStation] = []
    @State private var nearbyStations: [RailwayStation] = []
    
    var body: some View {
        NavigationStack {
            List {
                if searchResults.isEmpty && !searchQuery.isEmpty {
                    ContentUnavailableView(
                        "駅が見つかりません",
                        systemImage: "magnifyingglass",
                        description: Text("別のキーワードで検索してください")
                    )
                } else if searchQuery.isEmpty {
                    // 検索バーが空の時は近くの駅を表示
                    if nearbyStations.isEmpty {
                        ContentUnavailableView(
                            "駅名を入力",
                            systemImage: "tram.fill",
                            description: Text("検索バーに駅名を入力してください")
                        )
                    } else {
                        Section("現在地付近の駅") {
                            ForEach(nearbyStations) { station in
                                SearchResultRow(
                                    station: station,
                                    searchQuery: "",
                                    onSelect: {
                                        selectedStation = station
                                        dismiss()
                                    }
                                )
                            }
                        }
                    }
                } else {
                    ForEach(searchResults) { station in
                        SearchResultRow(
                            station: station,
                            searchQuery: searchQuery,
                            onSelect: {
                                selectedStation = station
                                dismiss()
                            }
                        )
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "駅名・別名を入力（例: 梅田）")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationManager.requestPermission()
                updateNearbyStations()
            }
            .onChange(of: searchQuery) { _, newValue in
                updateSearchResults(query: newValue)
            }
            .onChange(of: locationManager.currentLocation) { _, _ in
                if searchQuery.isEmpty {
                    updateNearbyStations()
                }
            }
        }
    }
    
    private func updateSearchResults(query: String) {
        if query.isEmpty {
            searchResults = []
        } else {
            let lat = locationManager.currentLocation?.coordinate.latitude
            let lon = locationManager.currentLocation?.coordinate.longitude
            searchResults = RouteSearchService.shared.searchStations(
                query: query,
                userLat: lat,
                userLon: lon
            )
        }
    }
    
    private func updateNearbyStations() {
        guard let location = locationManager.currentLocation else {
            nearbyStations = []
            return
        }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        nearbyStations = Array(
            RouteSearchService.shared.getAllStations()
                .sorted { s1, s2 in
                    distanceKm(from: lat, lon: lon, to: s1) < distanceKm(from: lat, lon: lon, to: s2)
                }
                .prefix(20)
        )
    }
    
    private func distanceKm(from lat1: Double, lon lon1: Double, to station: RailwayStation) -> Double {
        let lat2 = station.latitude
        let lon2 = station.longitude
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return 6371 * c
    }
}

// MARK: - Via Station Search View（経由駅追加用）

struct ViaStationSearchView: View {
    @Binding var viaStations: [RailwayStation]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var searchQuery = ""
    @State private var searchResults: [RailwayStation] = []
    @State private var nearbyStations: [RailwayStation] = []
    
    var body: some View {
        NavigationStack {
            List {
                if searchResults.isEmpty && !searchQuery.isEmpty {
                    ContentUnavailableView(
                        "駅が見つかりません",
                        systemImage: "magnifyingglass",
                        description: Text("別のキーワードで検索してください")
                    )
                } else if searchQuery.isEmpty {
                    // 検索バーが空の時は近くの駅を表示
                    if nearbyStations.isEmpty {
                        ContentUnavailableView(
                            "経由駅を検索",
                            systemImage: "arrow.triangle.swap",
                            description: Text("経由したい駅名を入力してください")
                        )
                    } else {
                        Section("現在地付近の駅") {
                            ForEach(nearbyStations) { station in
                                viaStationButton(station: station)
                            }
                        }
                    }
                } else {
                    ForEach(searchResults) { station in
                        viaStationButton(station: station)
                    }
                }
            }
            .navigationTitle("経由駅を追加")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "駅名を入力")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationManager.requestPermission()
                updateNearbyStations()
            }
            .onChange(of: searchQuery) { _, newValue in
                if newValue.isEmpty {
                    searchResults = []
                } else {
                    let lat = locationManager.currentLocation?.coordinate.latitude
                    let lon = locationManager.currentLocation?.coordinate.longitude
                    searchResults = RouteSearchService.shared.searchStations(
                        query: newValue,
                        userLat: lat,
                        userLon: lon
                    )
                }
            }
            .onChange(of: locationManager.currentLocation) { _, _ in
                if searchQuery.isEmpty {
                    updateNearbyStations()
                }
            }
        }
    }
    
    private func viaStationButton(station: RailwayStation) -> some View {
        Button {
            if !viaStations.contains(where: { $0.id == station.id }) {
                viaStations.append(station)
            }
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(station.lines.prefix(2).joined(separator: "・"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viaStations.contains(where: { $0.id == station.id }) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func updateNearbyStations() {
        guard let location = locationManager.currentLocation else {
            nearbyStations = []
            return
        }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        nearbyStations = Array(
            RouteSearchService.shared.getAllStations()
                .sorted { s1, s2 in
                    distanceKm(from: lat, lon: lon, to: s1) < distanceKm(from: lat, lon: lon, to: s2)
                }
                .prefix(20)
        )
    }
    
    private func distanceKm(from lat1: Double, lon lon1: Double, to station: RailwayStation) -> Double {
        let lat2 = station.latitude
        let lon2 = station.longitude
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return 6371 * c
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let station: RailwayStation
    let searchQuery: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(station.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    if let matchedAlias = findMatchedAlias() {
                        Text("(\(matchedAlias))")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                
                HStack {
                    Text(station.lines.prefix(3).joined(separator: "・"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if station.lines.count > 3 {
                        Text("他\(station.lines.count - 3)路線")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func findMatchedAlias() -> String? {
        guard let aliases = station.aliases else { return nil }
        let query = searchQuery.lowercased()
        
        if station.name.lowercased().contains(query) {
            return nil
        }
        
        return aliases.first { $0.lowercased().contains(query) }
    }
}

#Preview {
    TripInputView()
        .modelContainer(for: [Station.self, StationLog.self])
}
