import Foundation
import SwiftData
import Combine
import CoreLocation

@MainActor
class StationViewModel: ObservableObject {
    @Published var allStations: [Station] = []
    @Published var searchText: String = "" {
        didSet {
            // 検索テキストが変わったらデバウンス付きで検索実行
            scheduleSearch()
        }
    }
    @Published var isLoading: Bool = true  // ローディング状態
    @Published var cachedFilteredStations: [Station] = []  // 検索結果キャッシュ
    @Published var isSearching: Bool = false  // 検索中フラグ

    private var modelContext: ModelContext?
    private var stationDataCache: [RailwayStation] = []
    private var stationById: [String: RailwayStation] = [:]
    private var stationAliases: [String: [String]] = [:]  // id -> aliases

    // 統計キャッシュ
    private var cachedTotalStationCount: Int?
    private var cachedHomeStations: [Station]?
    private var cachedStatusCounts: [LogStatus: Int]?
    private var cachedPrefectureCounts: [String: Int]?
    private var cacheInvalidated = true

    // 駅ごとの最強ステータスキャッシュ（タブ移動高速化用）
    private var cachedStrongestStatus: [String: LogStatus] = [:]
    private var strongestStatusCacheValid = false

    // 検索デバウンス用
    private var searchTask: Task<Void, Never>?

    // 位置情報
    private let locationManager = LocationManager.shared

    init() {
        locationManager.requestPermission()
        // 非同期でロード開始
        Task {
            await loadStationsAsync()
        }
    }

    /// デバウンス付きで検索をスケジュール
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            // 0.15秒待つ（デバウンス）
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    /// バックグラウンドで検索実行
    private func performSearch() async {
        isSearching = true
        let query = searchText
        let stations = allStations
        let aliases = stationAliases
        let location = locationManager.currentLocation

        // バックグラウンドスレッドで検索
        let result = await Task.detached(priority: .userInitiated) { () -> [Station] in
            // 検索バーが空の場合 → 現在地から近い順
            if query.isEmpty {
                if let loc = location {
                    let userLat = loc.coordinate.latitude
                    let userLon = loc.coordinate.longitude
                    return stations.sorted {
                        Self.distance(from: userLat, lon: userLon, to: $0) < Self.distance(from: userLat, lon: userLon, to: $1)
                    }
                } else {
                    return stations
                }
            }

            let queryLower = query.lowercased()
            var exactMatch: [Station] = []
            var aliasExactMatch: [Station] = []
            var partialMatch: [Station] = []
            var aliasPartialMatch: [Station] = []

            for station in stations {
                let nameLower = station.name.lowercased()
                let stationAliases = aliases[station.id] ?? []

                if nameLower == queryLower {
                    exactMatch.append(station)
                } else if stationAliases.contains(where: { $0.lowercased() == queryLower }) {
                    aliasExactMatch.append(station)
                } else if nameLower.contains(queryLower) {
                    partialMatch.append(station)
                } else if stationAliases.contains(where: { $0.lowercased().contains(queryLower) }) {
                    aliasPartialMatch.append(station)
                }
            }

            // 部分一致は距離順（現在地がある場合）
            if let loc = location {
                let userLat = loc.coordinate.latitude
                let userLon = loc.coordinate.longitude
                partialMatch.sort { Self.distance(from: userLat, lon: userLon, to: $0) < Self.distance(from: userLat, lon: userLon, to: $1) }
                aliasPartialMatch.sort { Self.distance(from: userLat, lon: userLon, to: $0) < Self.distance(from: userLat, lon: userLon, to: $1) }
            } else {
                partialMatch.sort { $0.name.count < $1.name.count }
                aliasPartialMatch.sort { $0.name.count < $1.name.count }
            }

            return exactMatch + aliasExactMatch + partialMatch + aliasPartialMatch
        }.value

        // 最新の検索クエリと一致する場合のみ更新
        if searchText == query {
            cachedFilteredStations = result
        }
        isSearching = false
    }

    /// 距離計算（static版、バックグラウンドスレッドから呼ぶ用）
    nonisolated private static func distance(from lat1: Double, lon lon1: Double, to station: Station) -> Double {
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
    
    convenience init(modelContext: ModelContext) {
        self.init()
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// 非同期で駅データをロード（UIをブロックしない）
    private func loadStationsAsync() async {
        isLoading = true

        // バックグラウンドスレッドでJSONを読み込み・パース
        let result = await Task.detached(priority: .userInitiated) { () -> (stations: [Station], cache: [RailwayStation], byId: [String: RailwayStation], aliases: [String: [String]])? in
            guard let url = Bundle.main.url(forResource: "japan_stations", withExtension: "json") else {
                print("❌ japan_stations.json not found")
                return nil
            }

            do {
                let data = try Data(contentsOf: url)
                let railwayData = try JSONDecoder().decode(RailwayData.self, from: data)

                var byId: [String: RailwayStation] = [:]
                var aliases: [String: [String]] = [:]

                for station in railwayData.stations {
                    byId[station.id] = station
                    if let stationAliases = station.aliases, !stationAliases.isEmpty {
                        aliases[station.id] = stationAliases
                    }
                }

                let stations = railwayData.stations.map { s in
                    Station(id: s.id, name: s.name, prefecture: s.prefecture, latitude: s.latitude, longitude: s.longitude)
                }

                return (stations, railwayData.stations, byId, aliases)
            } catch {
                print("❌ Error loading stations: \(error)")
                return nil
            }
        }.value

        // メインスレッドでUI更新
        if let result = result {
            self.stationDataCache = result.cache
            self.stationById = result.byId
            self.stationAliases = result.aliases
            self.allStations = result.stations
            print("✅ Loaded \(allStations.count) stations")

            // 初回検索を実行
            await performSearch()
        }

        isLoading = false
    }

    func loadStations() {
        // 互換性のために残す（同期版）
        Task {
            await loadStationsAsync()
        }
    }
    
    /// 検索結果（キャッシュを返す）
    var filteredStations: [Station] {
        cachedFilteredStations
    }
    
    /// 2点間の距離を計算（簡易版、km）
    private func distance(from lat1: Double, lon lon1: Double, to station: Station) -> Double {
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
    
    func getStationData(byId id: String) -> RailwayStation? {
        return stationById[id]
    }
    
    func saveLog(station: Station, status: LogStatus, memo: String, tripId: UUID? = nil) {
        guard let context = modelContext else { return }

        // 最寄り駅（home）は複数設定可能
        // 同じ駅に同じステータスが既にある場合は追加しない
        if status == .home {
            let descriptor = FetchDescriptor<StationLog>()
            if let existingLogs = try? context.fetch(descriptor) {
                let alreadyHome = existingLogs.contains {
                    $0.stationId == station.id && $0.status == .home
                }
                if alreadyHome {
                    return  // 既に最寄り登録済み
                }
            }
        }

        let log = StationLog(stationId: station.id, stationName: station.name, status: status, memo: memo, tripId: tripId)
        context.insert(log)
        try? context.save()

        // 部分的キャッシュ更新（全体を無効化せず、該当駅だけ更新）
        updateStrongestStatusCache(for: station.id, newStatus: status)
        invalidateCacheExceptStrongestStatus()
    }

    /// ステータスキャッシュを部分更新（1駅だけ）
    private func updateStrongestStatusCache(for stationId: String, newStatus: LogStatus) {
        guard strongestStatusCacheValid else { return }

        let currentStatus = cachedStrongestStatus[stationId]

        // home/homeRemovedの場合は再計算が必要
        if newStatus == .home {
            cachedStrongestStatus[stationId] = .home
        } else if newStatus == .homeRemoved {
            // homeRemovedの場合、訪問系の最強を再計算する必要があるのでキャッシュ無効化
            strongestStatusCacheValid = false
        } else {
            // 訪問系ステータスの場合、既存より強ければ更新
            if let current = currentStatus {
                if current != .home && newStatus.strength > current.strength {
                    cachedStrongestStatus[stationId] = newStatus
                }
            } else {
                cachedStrongestStatus[stationId] = newStatus
            }
        }
    }

    /// 最強ステータスキャッシュ以外を無効化
    private func invalidateCacheExceptStrongestStatus() {
        cachedTotalStationCount = nil
        cachedHomeStations = nil
        cachedStatusCounts = nil
        cachedPrefectureCounts = nil
        cacheInvalidated = true
    }
    
    /// キャッシュを無効化
    func invalidateCache() {
        cachedTotalStationCount = nil
        cachedHomeStations = nil
        cachedStatusCounts = nil
        cachedPrefectureCounts = nil
        cacheInvalidated = true
        strongestStatusCacheValid = false
    }

    /// キャッシュを無効化して非同期で再構築（完了後にコールバック）
    func invalidateCacheAndRebuildAsync(completion: @escaping () -> Void) {
        invalidateCache()

        // バックグラウンドでキャッシュを再構築
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                // キャッシュを再構築（getStrongestStatusを呼ぶと内部でbuildStrongestStatusCacheが実行される）
                _ = self.getStrongestStatus(for: "")
            }
            await MainActor.run {
                completion()
            }
        }
    }
    
    /// 最寄り駅を解除（ログは削除せず、解除ログを追加）
    func removeHome(stationId: String) {
        guard let context = modelContext else { return }
        
        // 駅名を取得
        let stationName = getStation(byId: stationId)?.name ?? ""
        
        // 解除ログを追加
        let log = StationLog(
            stationId: stationId,
            stationName: stationName,
            status: .homeRemoved,
            memo: ""
        )
        context.insert(log)
        try? context.save()
        invalidateCache()
    }
    
    /// 全ての最寄り駅を取得（最新の最寄り関連ログが.homeの駅）
    func getHomeStations() -> [Station] {
        if let cached = cachedHomeStations {
            return cached
        }
        
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<StationLog>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let logs = try? context.fetch(descriptor) else { return [] }
        
        // 各駅の最新の最寄り関連ログ（.home または .homeRemoved）を取得
        var latestHomeStatus: [String: LogStatus] = [:]
        for log in logs {
            if log.status == .home || log.status == .homeRemoved {
                // まだこの駅の最寄り関連ログがなければ記録（最新順なので最初に見つかったものが最新）
                if latestHomeStatus[log.stationId] == nil {
                    latestHomeStatus[log.stationId] = log.status
                }
            }
        }
        
        // 最新が.homeの駅のみを返す
        let homeIds = latestHomeStatus.filter { $0.value == .home }.map { $0.key }
        let result = allStations.filter { homeIds.contains($0.id) }
        cachedHomeStations = result
        return result
    }
    
    func getStrongestStatus(for stationId: String) -> LogStatus? {
        // キャッシュが有効ならそれを返す
        if strongestStatusCacheValid {
            return cachedStrongestStatus[stationId]
        }

        // キャッシュを一括構築
        buildStrongestStatusCache()
        return cachedStrongestStatus[stationId]
    }

    /// 全駅のステータスキャッシュを一括構築（1回のフェッチで全駅分を計算）
    private func buildStrongestStatusCache() {
        guard let context = modelContext else {
            strongestStatusCacheValid = true
            return
        }

        let descriptor = FetchDescriptor<StationLog>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let logs = try? context.fetch(descriptor) else {
            strongestStatusCacheValid = true
            return
        }

        // 駅ごとにログをグループ化
        var logsByStation: [String: [StationLog]] = [:]
        for log in logs {
            logsByStation[log.stationId, default: []].append(log)
        }

        // 各駅の最強ステータスを計算
        var result: [String: LogStatus] = [:]
        for (stationId, stationLogs) in logsByStation {
            // 現在最寄りかどうかを判定
            let latestHomeLog = stationLogs.first { $0.status == .home || $0.status == .homeRemoved }
            let isCurrentlyHome = latestHomeLog?.status == .home

            if isCurrentlyHome {
                result[stationId] = .home
            } else {
                // 訪問系ステータスの最強を返す
                let visitStatuses: [LogStatus] = [.visited, .transferred, .passed]
                let visitLogs = stationLogs.filter { visitStatuses.contains($0.status) }
                if let strongest = visitLogs.map({ $0.status }).max(by: { $0.strength < $1.strength }) {
                    result[stationId] = strongest
                }
            }
        }

        cachedStrongestStatus = result
        strongestStatusCacheValid = true
    }
    
    func getLogs(for stationId: String) -> [StationLog] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<StationLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let logs = try? context.fetch(descriptor) else { return [] }
        
        return logs.filter { $0.stationId == stationId }
    }
    
    func getTotalStationCount() -> Int {
        if let cached = cachedTotalStationCount {
            return cached
        }
        
        guard let context = modelContext else { return 0 }
        let descriptor = FetchDescriptor<StationLog>()
        guard let logs = try? context.fetch(descriptor) else { return 0 }
        
        let uniqueIds = Set(logs.map { $0.stationId })
        cachedTotalStationCount = uniqueIds.count
        return uniqueIds.count
    }
    
    func getStatusCount(status: LogStatus) -> Int {
        // キャッシュがあれば使う
        if let cached = cachedStatusCounts {
            return cached[status] ?? 0
        }
        
        guard let context = modelContext else { return 0 }
        let descriptor = FetchDescriptor<StationLog>()
        guard let logs = try? context.fetch(descriptor) else { return 0 }
        
        // 駅IDでグループ化
        var logsByStation: [String: [StationLog]] = [:]
        for log in logs {
            logsByStation[log.stationId, default: []].append(log)
        }
        
        // 全ステータスのカウントを一度に計算してキャッシュ
        var counts: [LogStatus: Int] = [:]
        for (_, stationLogs) in logsByStation {
            if let strongest = stationLogs.map({ $0.status }).max(by: { $0.strength < $1.strength }) {
                counts[strongest, default: 0] += 1
            }
        }
        cachedStatusCounts = counts
        return counts[status] ?? 0
    }
    
    func getPrefectureCount() -> [String: Int] {
        if let cached = cachedPrefectureCounts {
            return cached
        }
        
        guard let context = modelContext else { return [:] }
        let descriptor = FetchDescriptor<StationLog>()
        guard let logs = try? context.fetch(descriptor) else { return [:] }
        
        let loggedIds = Set(logs.map { $0.stationId })
        var counts: [String: Int] = [:]
        
        for loggedId in loggedIds {
            if let station = stationById[loggedId] {
                let pref = station.prefecture.isEmpty ? "不明" : station.prefecture
                counts[pref, default: 0] += 1
            }
        }
        cachedPrefectureCounts = counts
        return counts
    }
    
    func getStation(byId id: String) -> Station? {
        return allStations.first(where: { $0.id == id })
    }
    
    /// エイリアスを取得
    func getAliases(for stationId: String) -> [String] {
        return stationAliases[stationId] ?? []
    }
}
