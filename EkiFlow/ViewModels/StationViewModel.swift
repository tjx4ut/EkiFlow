import Foundation
import SwiftData
import Combine
import CoreLocation

@MainActor
class StationViewModel: ObservableObject {
    @Published var allStations: [Station] = []
    @Published var searchText: String = ""
    
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
    
    // 位置情報
    private let locationManager = LocationManager.shared
    
    init() {
        loadStations()
        locationManager.requestPermission()
    }
    
    convenience init(modelContext: ModelContext) {
        self.init()
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func loadStations() {
        // 新しいファイル名: japan_stations.json
        guard let url = Bundle.main.url(forResource: "japan_stations", withExtension: "json") else {
            print("❌ japan_stations.json not found")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let railwayData = try JSONDecoder().decode(RailwayData.self, from: data)
            stationDataCache = railwayData.stations
            
            // ID→駅のマッピングとエイリアスを保存
            for station in railwayData.stations {
                stationById[station.id] = station
                if let aliases = station.aliases, !aliases.isEmpty {
                    stationAliases[station.id] = aliases
                }
            }
            
            allStations = railwayData.stations.map { s in
                Station(id: s.id, name: s.name, prefecture: s.prefecture, latitude: s.latitude, longitude: s.longitude)
            }
            print("✅ Loaded \(allStations.count) stations")
        } catch {
            print("❌ Error loading stations: \(error)")
        }
    }
    
    /// 検索結果（完全一致 → 別名完全一致 → 部分一致(距離順) → 別名部分一致(距離順)）
    /// 検索バーが空の時は現在地から近い順
    var filteredStations: [Station] {
        // 検索バーが空の場合 → 現在地から近い順
        if searchText.isEmpty {
            if let location = locationManager.currentLocation {
                let userLat = location.coordinate.latitude
                let userLon = location.coordinate.longitude
                return allStations.sorted {
                    distance(from: userLat, lon: userLon, to: $0) < distance(from: userLat, lon: userLon, to: $1)
                }
            } else {
                return allStations
            }
        }
        
        let query = searchText.lowercased()
        
        var exactMatch: [Station] = []
        var aliasExactMatch: [Station] = []
        var partialMatch: [Station] = []
        var aliasPartialMatch: [Station] = []
        
        for station in allStations {
            let nameLower = station.name.lowercased()
            let aliases = stationAliases[station.id] ?? []
            
            // 駅名完全一致
            if nameLower == query {
                exactMatch.append(station)
                continue
            }
            
            // 別名完全一致
            if aliases.contains(where: { $0.lowercased() == query }) {
                aliasExactMatch.append(station)
                continue
            }
            
            // 駅名部分一致
            if nameLower.contains(query) {
                partialMatch.append(station)
                continue
            }
            
            // 別名部分一致
            if aliases.contains(where: { $0.lowercased().contains(query) }) {
                aliasPartialMatch.append(station)
            }
        }
        
        // 部分一致は距離順（現在地がある場合）
        if let location = locationManager.currentLocation {
            let userLat = location.coordinate.latitude
            let userLon = location.coordinate.longitude
            
            partialMatch.sort { distance(from: userLat, lon: userLon, to: $0) < distance(from: userLat, lon: userLon, to: $1) }
            aliasPartialMatch.sort { distance(from: userLat, lon: userLon, to: $0) < distance(from: userLat, lon: userLon, to: $1) }
        } else {
            // 現在地がない場合は名前の短い順
            partialMatch.sort { $0.name.count < $1.name.count }
            aliasPartialMatch.sort { $0.name.count < $1.name.count }
        }
        
        return exactMatch + aliasExactMatch + partialMatch + aliasPartialMatch
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
        invalidateCache()
    }
    
    /// キャッシュを無効化
    func invalidateCache() {
        cachedTotalStationCount = nil
        cachedHomeStations = nil
        cachedStatusCounts = nil
        cachedPrefectureCounts = nil
        cacheInvalidated = true
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
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<StationLog>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let logs = try? context.fetch(descriptor) else { return nil }
        
        let stationLogs = logs.filter { $0.stationId == stationId }
        
        // 現在最寄りかどうかを判定（最新の最寄り関連ログが.homeかどうか）
        let latestHomeLog = stationLogs.first { $0.status == .home || $0.status == .homeRemoved }
        let isCurrentlyHome = latestHomeLog?.status == .home
        
        if isCurrentlyHome {
            return .home
        }
        
        // 訪問系ステータス（visited, transferred, passed）の最強を返す
        let visitStatuses: [LogStatus] = [.visited, .transferred, .passed]
        let visitLogs = stationLogs.filter { visitStatuses.contains($0.status) }
        return visitLogs.map { $0.status }.max(by: { $0.strength < $1.strength })
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
