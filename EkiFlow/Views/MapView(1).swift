import SwiftUI
import MapKit
import SwiftData

// MARK: - 桜カラーテーマ
extension Color {
    static let sakuraPink = Color(red: 0.973, green: 0.647, blue: 0.761)      // #F8A5C2 満開の花
    static let sakuraPetal = Color(red: 0.980, green: 0.855, blue: 0.867)     // #FADADD 花びら
    static let sakuraBark = Color(red: 0.545, green: 0.451, blue: 0.333)      // #8B7355 木の幹
    static let sakuraLeaf = Color(red: 0.486, green: 0.714, blue: 0.557)      // #7CB68E 若葉
}

struct MapView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @Query private var logs: [StationLog]
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedStation: Station?
    
    // キャッシュ（logsが変わった時だけ再計算）
    @State private var stationsByStatus: [LogStatus: [Station]] = [:]
    @State private var cachedVisitedPrefectures: Set<String> = []
    @State private var isInitialized = false
    
    // 訪問済み都道府県（キャッシュから取得）
    private var visitedPrefectures: Set<String> {
        cachedVisitedPrefectures
    }
    
    // キャッシュを再計算
    private func recalculateCache() {
        // 1回のループで全駅のステータスを計算
        var statusByStationId: [String: LogStatus] = [:]
        var prefectures: Set<String> = []
        
        // ログを駅IDでグループ化（1回のループで完了）
        var logsByStation: [String: [StationLog]] = [:]
        for log in logs {
            logsByStation[log.stationId, default: []].append(log)
        }
        
        // 各駅の最強ステータスを計算
        for (stationId, stationLogs) in logsByStation {
            if let strongest = stationLogs.map({ $0.status }).max(by: { $0.strength < $1.strength }) {
                statusByStationId[stationId] = strongest
            }
            // 都道府県も同時に収集
            if let pref = viewModel.getStationData(byId: stationId)?.prefecture {
                prefectures.insert(pref)
            }
        }
        
        // ステータスごとに駅を分類
        var newStationsByStatus: [LogStatus: [Station]] = [
            .passed: [],
            .transferred: [],
            .visited: [],
            .home: []
        ]
        
        for station in viewModel.allStations {
            if let status = statusByStationId[station.id] {
                newStationsByStatus[status, default: []].append(station)
            }
        }
        
        stationsByStatus = newStationsByStatus
        cachedVisitedPrefectures = prefectures
    }
    
    // 特定のステータスを持つ駅を取得（キャッシュから）
    private func stationsWithStatus(_ targetStatus: LogStatus) -> [Station] {
        stationsByStatus[targetStatus] ?? []
    }
    
    var body: some View {
        ZStack {
            if !isInitialized {
                // ローディング表示
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("マップを読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Map(position: $cameraPosition) {
                // ステータスごとに分けて描画（後に描画されるものが上に来る）
                
                // 1. 通過（茶色）← 一番下
                ForEach(stationsWithStatus(.passed)) { station in
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude,
                            longitude: station.longitude
                        )
                    ) {
                        StationMarker(status: .passed)
                            .onTapGesture { selectedStation = station }
                    }
                }
                
                // 2. 乗換（薄桜）
                ForEach(stationsWithStatus(.transferred)) { station in
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude,
                            longitude: station.longitude
                        )
                    ) {
                        StationMarker(status: .transferred)
                            .onTapGesture { selectedStation = station }
                    }
                }
                
                // 3. 行った（ピンク）
                ForEach(stationsWithStatus(.visited)) { station in
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude,
                            longitude: station.longitude
                        )
                    ) {
                        StationMarker(status: .visited)
                            .onTapGesture { selectedStation = station }
                    }
                }
                
                // 4. 最寄り（緑）← 一番上
                ForEach(stationsWithStatus(.home)) { station in
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude,
                            longitude: station.longitude
                        )
                    ) {
                        StationMarker(status: .home)
                            .onTapGesture { selectedStation = station }
                    }
                }
            }
            .mapStyle(.standard)
            
            // 現在地ボタン（右下）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        moveToCurrentLocation()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 100) // 凡例の上
                }
            }
            
            // 凡例
            VStack {
                Spacer()
                HStack {
                    legendItem(color: .sakuraPink, label: "行った")
                    legendItem(color: .sakuraPetal, label: "乗換")
                    legendItem(color: .sakuraBark, label: "通過")
                    legendItem(color: .sakuraLeaf, label: "最寄り")
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            }
            
            // 都道府県訪問状況
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("訪問都道府県")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(visitedPrefectures.count) / 47")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
                Spacer()
            }
            } // else閉じ
        }
        .sheet(item: $selectedStation) { station in
            StationDetailView(station: station, showCloseButton: true)
        }
        .onAppear {
            // 初回のみキャッシュ計算
            if !isInitialized {
                recalculateCache()
                isInitialized = true
            }
            // 日本全体を表示
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.0),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 15)
            ))
        }
        .onChange(of: logs.count) { _, _ in
            // ログ数が変わったら再計算
            recalculateCache()
        }
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
        }
    }
    
    private func moveToCurrentLocation() {
        let locationManager = LocationManager.shared
        
        // 位置情報の更新を開始
        locationManager.startUpdating()
        
        // 少し待ってから移動（位置情報取得に時間がかかる場合があるため）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let location = locationManager.currentLocation {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
            } else {
                // 位置情報が取れない場合は東京駅をデフォルトに
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
        }
    }
}

// MARK: - Station Marker（色付き丸マーカー）

struct StationMarker: View {
    let status: LogStatus?
    
    var body: some View {
        Circle()
            .fill(markerColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
            )
            .shadow(color: markerColor.opacity(0.5), radius: 2)
    }
    
    private var markerColor: Color {
        guard let status = status else { return .sakuraBark }
        switch status {
        case .visited: return .sakuraPink
        case .transferred: return .sakuraPetal
        case .passed: return .sakuraBark
        case .home: return .sakuraLeaf
        case .homeRemoved: return .sakuraBark  // 実際には使われない（getStrongestStatusから除外）
        }
    }
}

// MARK: - Prefecture Map View（都道府県別の塗り分け）

struct PrefectureMapView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @Query private var logs: [StationLog]
    
    // キャッシュ
    @State private var cachedVisitedPrefectures: Set<String> = []
    
    // 訪問済み都道府県（キャッシュから）
    private var visitedPrefectures: Set<String> {
        cachedVisitedPrefectures
    }
    
    private func recalculatePrefectures() {
        var prefectures: Set<String> = []
        let uniqueStationIds = Set(logs.map { $0.stationId })
        for stationId in uniqueStationIds {
            if let pref = viewModel.getStationData(byId: stationId)?.prefecture {
                prefectures.insert(pref)
            }
        }
        cachedVisitedPrefectures = prefectures
    }
    
    // 都道府県の中心座標
    private let prefectureCoordinates: [String: CLLocationCoordinate2D] = [
        "北海道": CLLocationCoordinate2D(latitude: 43.06, longitude: 141.35),
        "青森県": CLLocationCoordinate2D(latitude: 40.82, longitude: 140.74),
        "岩手県": CLLocationCoordinate2D(latitude: 39.70, longitude: 141.15),
        "宮城県": CLLocationCoordinate2D(latitude: 38.27, longitude: 140.87),
        "秋田県": CLLocationCoordinate2D(latitude: 39.72, longitude: 140.10),
        "山形県": CLLocationCoordinate2D(latitude: 38.24, longitude: 140.33),
        "福島県": CLLocationCoordinate2D(latitude: 37.75, longitude: 140.47),
        "茨城県": CLLocationCoordinate2D(latitude: 36.34, longitude: 140.45),
        "栃木県": CLLocationCoordinate2D(latitude: 36.57, longitude: 139.88),
        "群馬県": CLLocationCoordinate2D(latitude: 36.39, longitude: 139.06),
        "埼玉県": CLLocationCoordinate2D(latitude: 35.86, longitude: 139.65),
        "千葉県": CLLocationCoordinate2D(latitude: 35.61, longitude: 140.12),
        "東京都": CLLocationCoordinate2D(latitude: 35.69, longitude: 139.69),
        "神奈川県": CLLocationCoordinate2D(latitude: 35.45, longitude: 139.64),
        "新潟県": CLLocationCoordinate2D(latitude: 37.90, longitude: 139.02),
        "富山県": CLLocationCoordinate2D(latitude: 36.70, longitude: 137.21),
        "石川県": CLLocationCoordinate2D(latitude: 36.59, longitude: 136.63),
        "福井県": CLLocationCoordinate2D(latitude: 36.07, longitude: 136.22),
        "山梨県": CLLocationCoordinate2D(latitude: 35.66, longitude: 138.57),
        "長野県": CLLocationCoordinate2D(latitude: 36.65, longitude: 138.18),
        "岐阜県": CLLocationCoordinate2D(latitude: 35.39, longitude: 136.72),
        "静岡県": CLLocationCoordinate2D(latitude: 34.98, longitude: 138.38),
        "愛知県": CLLocationCoordinate2D(latitude: 35.18, longitude: 136.91),
        "三重県": CLLocationCoordinate2D(latitude: 34.73, longitude: 136.51),
        "滋賀県": CLLocationCoordinate2D(latitude: 35.00, longitude: 135.87),
        "京都府": CLLocationCoordinate2D(latitude: 35.02, longitude: 135.76),
        "大阪府": CLLocationCoordinate2D(latitude: 34.69, longitude: 135.52),
        "兵庫県": CLLocationCoordinate2D(latitude: 34.69, longitude: 135.18),
        "奈良県": CLLocationCoordinate2D(latitude: 34.69, longitude: 135.83),
        "和歌山県": CLLocationCoordinate2D(latitude: 34.23, longitude: 135.17),
        "鳥取県": CLLocationCoordinate2D(latitude: 35.50, longitude: 134.24),
        "島根県": CLLocationCoordinate2D(latitude: 35.47, longitude: 133.05),
        "岡山県": CLLocationCoordinate2D(latitude: 34.66, longitude: 133.93),
        "広島県": CLLocationCoordinate2D(latitude: 34.40, longitude: 132.46),
        "山口県": CLLocationCoordinate2D(latitude: 34.19, longitude: 131.47),
        "徳島県": CLLocationCoordinate2D(latitude: 34.07, longitude: 134.56),
        "香川県": CLLocationCoordinate2D(latitude: 34.34, longitude: 134.04),
        "愛媛県": CLLocationCoordinate2D(latitude: 33.84, longitude: 132.77),
        "高知県": CLLocationCoordinate2D(latitude: 33.56, longitude: 133.53),
        "福岡県": CLLocationCoordinate2D(latitude: 33.61, longitude: 130.42),
        "佐賀県": CLLocationCoordinate2D(latitude: 33.25, longitude: 130.30),
        "長崎県": CLLocationCoordinate2D(latitude: 32.74, longitude: 129.87),
        "熊本県": CLLocationCoordinate2D(latitude: 32.79, longitude: 130.74),
        "大分県": CLLocationCoordinate2D(latitude: 33.24, longitude: 131.61),
        "宮崎県": CLLocationCoordinate2D(latitude: 31.91, longitude: 131.42),
        "鹿児島県": CLLocationCoordinate2D(latitude: 31.56, longitude: 130.56),
        "沖縄県": CLLocationCoordinate2D(latitude: 26.21, longitude: 127.68)
    ]
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $cameraPosition) {
            // 都道府県マーカー
            ForEach(Array(prefectureCoordinates.keys), id: \.self) { pref in
                if let coord = prefectureCoordinates[pref] {
                    Annotation(pref, coordinate: coord) {
                        PrefectureMarker(
                            name: pref,
                            isVisited: visitedPrefectures.contains(pref)
                        )
                    }
                }
            }
        }
        .mapStyle(.standard)
        .onAppear {
            recalculatePrefectures()
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.0),
                span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
            ))
        }
        .onChange(of: logs.count) { _, _ in
            recalculatePrefectures()
        }
    }
}

struct PrefectureMarker: View {
    let name: String
    let isVisited: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(isVisited ? Color.sakuraPink.opacity(0.8) : Color.sakuraBark.opacity(0.3))
                .frame(width: isVisited ? 20 : 12, height: isVisited ? 20 : 12)
                .overlay(
                    Circle()
                        .stroke(isVisited ? Color.sakuraPink : Color.sakuraBark, lineWidth: 2)
                )
            
            if isVisited {
                Text(String(name.prefix(2)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.sakuraPink)
            }
        }
    }
}

#Preview {
    MapView()
        .environmentObject(StationViewModel())
}
