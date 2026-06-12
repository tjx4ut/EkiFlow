import Foundation

// MARK: - JSON Data Models

struct RailwayStation: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let prefecture: String
    let latitude: Double
    let longitude: Double
    let lines: [String]
    let aliases: [String]?
    
    static func == (lhs: RailwayStation, rhs: RailwayStation) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct RailwayConnection: Codable {
    let from: String
    let to: String
    let line: String
    let duration: Int  // 所要時間（分）
}

struct RailwayLine: Codable {
    let name: String
    let reading: String
}

struct RailwayData: Codable {
    let stations: [RailwayStation]
    let connections: [RailwayConnection]
    let lines: [RailwayLine]?
}

// MARK: - Route Stop

struct RouteStop: Identifiable {
    let id = UUID()
    let stationId: String
    let stationName: String
    let prefecture: String
    let latitude: Double
    let longitude: Double
    let status: RouteStopStatus
    var line: String?  // varに変更（選択可能に）
    var alternativeLines: [String]  // 代替路線リスト
    
    enum RouteStopStatus {
        case departure
        case arrival
        case transfer
        case pass
        
        var displayName: String {
            switch self {
            case .departure: return "出発"
            case .arrival: return "到着"
            case .transfer: return "乗換"
            case .pass: return "通過"
            }
        }
    }
}

// MARK: - Route Search Service

class RouteSearchService {
    static let shared = RouteSearchService()
    
    private var stations: [RailwayStation] = []
    private var connections: [RailwayConnection] = []
    private var stationById: [String: RailwayStation] = [:]
    private var adjacencyList: [String: [(neighbor: String, line: String, duration: Int)]] = [:]
    private var lineReadings: [String: String] = [:]  // 路線名 -> 読み仮名
    
    private init() {
        loadData()
    }
    
    private func loadData() {
        guard let url = Bundle.main.url(forResource: "japan_stations", withExtension: "json") else {
            print("❌ japan_stations.json not found")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let railwayData = try JSONDecoder().decode(RailwayData.self, from: data)
            
            self.stations = railwayData.stations
            self.connections = railwayData.connections
            
            // ID→駅のマッピング
            for station in stations {
                stationById[station.id] = station
            }
            
            // 隣接リスト構築（所要時間付き）
            // 駅リストに存在しないIDを参照する接続（廃線の残骸）は除外する
            for connection in connections {
                guard stationById[connection.from] != nil, stationById[connection.to] != nil else {
                    continue
                }
                if adjacencyList[connection.from] == nil {
                    adjacencyList[connection.from] = []
                }
                if adjacencyList[connection.to] == nil {
                    adjacencyList[connection.to] = []
                }
                adjacencyList[connection.from]?.append((connection.to, connection.line, connection.duration))
                adjacencyList[connection.to]?.append((connection.from, connection.line, connection.duration))
            }
            
            // 路線読み仮名のマッピング
            if let lines = railwayData.lines {
                for line in lines {
                    lineReadings[line.name] = line.reading
                }
            }
            
            print("✅ Loaded \(stations.count) stations, \(connections.count) connections, \(lineReadings.count) line readings")
        } catch {
            print("❌ Failed to load station data: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// 駅名・エイリアスで検索
    /// 優先順位: 完全一致 → 別名完全一致 → 部分一致(距離順) → 別名部分一致(距離順)
    func searchStations(query: String, userLat: Double? = nil, userLon: Double? = nil) -> [RailwayStation] {
        let query = query.lowercased()
        
        var exactMatch: [RailwayStation] = []        // 駅名完全一致
        var aliasExactMatch: [RailwayStation] = []   // 別名完全一致
        var partialMatch: [RailwayStation] = []      // 駅名部分一致
        var aliasPartialMatch: [RailwayStation] = [] // 別名部分一致
        
        for station in stations {
            let nameLower = station.name.lowercased()
            
            // 駅名完全一致
            if nameLower == query {
                exactMatch.append(station)
                continue
            }
            
            // 別名完全一致
            if let aliases = station.aliases {
                if aliases.contains(where: { $0.lowercased() == query }) {
                    aliasExactMatch.append(station)
                    continue
                }
            }
            
            // 駅名部分一致
            if nameLower.contains(query) {
                partialMatch.append(station)
                continue
            }
            
            // 別名部分一致
            if let aliases = station.aliases {
                if aliases.contains(where: { $0.lowercased().contains(query) }) {
                    aliasPartialMatch.append(station)
                }
            }
        }
        
        // 部分一致は距離順（現在地がある場合）
        if let lat = userLat, let lon = userLon {
            partialMatch.sort { distance(from: lat, lon: lon, to: $0) < distance(from: lat, lon: lon, to: $1) }
            aliasPartialMatch.sort { distance(from: lat, lon: lon, to: $0) < distance(from: lat, lon: lon, to: $1) }
        } else {
            // 現在地がない場合は名前の短い順
            partialMatch.sort { $0.name.count < $1.name.count }
            aliasPartialMatch.sort { $0.name.count < $1.name.count }
        }
        
        // 結合して返す
        let result = exactMatch + aliasExactMatch + partialMatch + aliasPartialMatch
        return Array(result.prefix(50))
    }
    
    /// 2点間の距離を計算（簡易版、km）
    private func distance(from lat1: Double, lon lon1: Double, to station: RailwayStation) -> Double {
        let lat2 = station.latitude
        let lon2 = station.longitude
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return 6371 * c  // 地球の半径(km)
    }
    
    /// IDで駅を取得
    func getStation(byId id: String) -> RailwayStation? {
        return stationById[id]
    }
    
    /// 全駅を取得
    func getAllStations() -> [RailwayStation] {
        return stations
    }

    /// 徒歩接続駅を取得
    func getWalkingConnections(for stationId: String) -> [(station: RailwayStation, duration: Int)] {
        guard let neighbors = adjacencyList[stationId] else { return [] }

        return neighbors
            .filter { $0.line == "徒歩" }
            .compactMap { neighbor -> (station: RailwayStation, duration: Int)? in
                guard let station = stationById[neighbor.neighbor] else { return nil }
                return (station: station, duration: neighbor.duration)
            }
    }

    /// ルートの所要時間を計算（分）
    func calculateRouteDuration(route: [RouteStop]) -> Int {
        guard route.count > 1 else { return 0 }
        
        var totalDuration = 0
        for i in 0..<(route.count - 1) {
            let fromId = route[i].stationId
            let toId = route[i + 1].stationId
            let chosenLine = route[i + 1].line

            // 隣接リストから所要時間を取得（選択中の路線のエッジを優先）
            if let neighbors = adjacencyList[fromId] {
                let edge = neighbors.first(where: { $0.neighbor == toId && $0.line == chosenLine })
                    ?? neighbors.first(where: { $0.neighbor == toId })
                totalDuration += edge?.duration ?? 3  // 見つからない場合はデフォルト3分
            } else {
                totalDuration += 3
            }
        }
        return totalDuration
    }
    
    // MARK: - Single Route Search
    
    /// 単一ルート検索（BFS）
    func findRoute(fromId: String, toId: String) -> [RouteStop]? {
        guard let result = dijkstraPath(from: fromId, to: toId, excludedEdges: []) else {
            return nil
        }
        let simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
        return buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false)
    }
    
    // MARK: - Line Search（路線検索）
    
    /// 全路線名のリストを取得
    func getAllLines() -> [String] {
        var lineSet = Set<String>()
        for station in stations {
            for line in station.lines {
                if line != "徒歩" {
                    lineSet.insert(line)
                }
            }
        }
        return lineSet.sorted()
    }
    
    /// 路線名で路線を検索（読み仮名対応）
    func searchLines(query: String) -> [String] {
        let query = query.lowercased()
        if query.isEmpty { return [] }
        
        return getAllLines().filter { line in
            // 路線名で検索
            if line.lowercased().contains(query) {
                return true
            }
            // 読み仮名で検索
            if let reading = lineReadings[line], reading.contains(query) {
                return true
            }
            return false
        }
    }
    
    /// 近くの路線を取得
    func getNearbyLines(latitude: Double, longitude: Double, limit: Int) -> [String] {
        // 全駅から距離を計算してソート
        let sortedStations = stations.sorted { s1, s2 in
            let d1 = distance(from: latitude, lon: longitude, to: s1)
            let d2 = distance(from: latitude, lon: longitude, to: s2)
            return d1 < d2
        }
        
        // 近い駅の路線を収集（重複排除）
        var lineSet = Set<String>()
        var lineOrder: [String] = []
        for station in sortedStations.prefix(30) {
            for line in station.lines {
                if !lineSet.contains(line) {
                    lineSet.insert(line)
                    lineOrder.append(line)
                }
                if lineOrder.count >= limit { break }
            }
            if lineOrder.count >= limit { break }
        }
        
        return lineOrder
    }
    
    /// 路線の読み仮名を取得
    func getLineReading(_ lineName: String) -> String? {
        return lineReadings[lineName]
    }
    
    /// 指定路線の全駅を取得（路線順）
    func getStationsForLine(_ lineName: String) -> [RailwayStation] {
        // その路線を持つ全駅を取得
        let lineStations = stations.filter { $0.lines.contains(lineName) }
        
        // 路線順に並べ替え（接続を辿る）
        guard !lineStations.isEmpty else { return [] }
        
        // 接続情報から路線の順序を構築
        var orderedStations: [RailwayStation] = []
        var visited = Set<String>()
        
        // 始点を見つける（接続が1つだけの駅 = 終端駅）
        var startStation = lineStations.first!
        for station in lineStations {
            let lineConnections = adjacencyList[station.id]?.filter { $0.line == lineName } ?? []
            if lineConnections.count == 1 {
                startStation = station
                break
            }
        }
        
        // DFSで順番に辿る
        var stack = [startStation]
        while !stack.isEmpty {
            let current = stack.removeLast()
            if visited.contains(current.id) { continue }
            visited.insert(current.id)
            orderedStations.append(current)
            
            // 同じ路線で繋がってる隣の駅を追加
            if let neighbors = adjacencyList[current.id] {
                for (neighborId, line, _) in neighbors {
                    if line == lineName && !visited.contains(neighborId) {
                        if let neighbor = stationById[neighborId] {
                            stack.append(neighbor)
                        }
                    }
                }
            }
        }
        
        // 訪問できなかった駅も追加（環状線などの場合）
        for station in lineStations {
            if !visited.contains(station.id) {
                orderedStations.append(station)
            }
        }
        
        return orderedStations
    }
    
    // MARK: - Multiple Routes Search
    
    /// 複数ルート検索（最大maxRoutes件）- スコア順でソート
    /// 出発駅からの各方向 + 到着駅への各方向でダイクストラ探索
    func findMultipleRoutes(fromId: String, toId: String, maxRoutes: Int = 5, useShinkansen: Bool = true, useLimitedExpress: Bool = true) -> [[RouteStop]] {
        var results: [(route: [RouteStop], duration: Int, transfers: Int)] = []
        var usedPaths: Set<String> = []
        
        let transferPenalty = 5
        let firstNeighbors = adjacencyList[fromId] ?? []
        let lastNeighbors = adjacencyList[toId] ?? []  // 到着駅に繋がってる駅
        
        // 1. まず最短ルートを見つける
        var shortestDuration = Int.max
        if let result = dijkstraPath(from: fromId, to: toId, excludedEdges: [], useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) {
            let simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
            let pathHash = simplePath.map { $0.id }.joined(separator: "-")
            usedPaths.insert(pathHash)
            shortestDuration = result.totalDuration
            
            if let route = buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false) {
                let transfers = route.filter { $0.status == .transfer }.count
                results.append((route, result.totalDuration, transfers))
            }
        }
        
        // 遠回り判定の閾値（最短の1.8倍まで許容）
        let maxAllowedDuration = shortestDuration == Int.max ? Int.max : Int(Double(shortestDuration) * 1.8)
        
        // 2. 出発駅からの各方向で探索
        for firstEdge in firstNeighbors {
            if results.count >= maxRoutes * 3 { break }
            
            // 新幹線・特急フィルター
            if !useShinkansen && firstEdge.line.contains("新幹線") { continue }
            if !useLimitedExpress && (firstEdge.line.contains("特急") || firstEdge.line.contains("エクスプレス") || firstEdge.line.contains("ライナー")) { continue }
            
            // この方向以外を除外
            var excludedEdges: Set<String> = []
            for otherEdge in firstNeighbors where otherEdge.neighbor != firstEdge.neighbor {
                excludedEdges.insert("\(fromId)-\(otherEdge.neighbor)")
            }
            
            if let result = dijkstraPath(from: fromId, to: toId, excludedEdges: excludedEdges, useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) {
                // 遠回りすぎるルートは除外
                if result.totalDuration > maxAllowedDuration { continue }
                
                let simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
                let pathHash = simplePath.map { $0.id }.joined(separator: "-")
                
                if !usedPaths.contains(pathHash) {
                    usedPaths.insert(pathHash)
                    if let route = buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false) {
                        let transfers = route.filter { $0.status == .transfer }.count
                        results.append((route, result.totalDuration, transfers))
                    }
                }
            }
        }
        
        // 3. 到着駅への各方向で探索（徒歩で到着するルートなど）
        for lastEdge in lastNeighbors {
            if results.count >= maxRoutes * 3 { break }
            
            // 新幹線・特急フィルター
            if !useShinkansen && lastEdge.line.contains("新幹線") { continue }
            if !useLimitedExpress && (lastEdge.line.contains("特急") || lastEdge.line.contains("エクスプレス") || lastEdge.line.contains("ライナー")) { continue }
            
            // この方向以外を除外（到着駅への他のエッジを除外）
            var excludedEdges: Set<String> = []
            for otherEdge in lastNeighbors where otherEdge.neighbor != lastEdge.neighbor {
                excludedEdges.insert("\(otherEdge.neighbor)-\(toId)")
                excludedEdges.insert("\(toId)-\(otherEdge.neighbor)")
            }
            
            if let result = dijkstraPath(from: fromId, to: toId, excludedEdges: excludedEdges, useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) {
                // 遠回りすぎるルートは除外
                if result.totalDuration > maxAllowedDuration { continue }
                
                let simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
                let pathHash = simplePath.map { $0.id }.joined(separator: "-")
                
                if !usedPaths.contains(pathHash) {
                    usedPaths.insert(pathHash)
                    if let route = buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false) {
                        let transfers = route.filter { $0.status == .transfer }.count
                        results.append((route, result.totalDuration, transfers))
                    }
                }
            }
        }
        
        // 4. 徒歩で到着するルートを強制探索
        let walkEdgesToGoal = lastNeighbors.filter { $0.line == "徒歩" }
        for walkEdge in walkEdgesToGoal {
            if results.count >= maxRoutes * 3 { break }
            
            let walkFromStation = walkEdge.neighbor
            
            // 目的地を経由せずに徒歩接続元まで行くルートを探す
            // 目的地への直接エッジを全て除外
            var excludedEdges: Set<String> = []
            for edge in lastNeighbors {
                excludedEdges.insert("\(edge.neighbor)-\(toId)")
                excludedEdges.insert("\(toId)-\(edge.neighbor)")
            }
            
            if let result = dijkstraPath(from: fromId, to: walkFromStation, excludedEdges: excludedEdges, useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) {
                let totalDuration = result.totalDuration + walkEdge.duration
                if totalDuration > maxAllowedDuration { continue }
                
                // 徒歩部分を追加したパスを作成
                var simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
                simplePath.append((id: toId, line: "徒歩"))
                
                let pathHash = simplePath.map { $0.id }.joined(separator: "-")
                
                if !usedPaths.contains(pathHash) {
                    usedPaths.insert(pathHash)
                    if let route = buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false) {
                        let transfers = route.filter { $0.status == .transfer }.count
                        results.append((route, totalDuration, transfers))
                    }
                }
            }
        }
        
        // 5. 既存ルートの中間を除外して更に探索
        let currentCount = results.count
        for i in 0..<min(currentCount, 3) {
            if results.count >= maxRoutes * 3 { break }
            
            let existingRoute = results[i].route
            if existingRoute.count > 4 {
                var excludedEdges: Set<String> = []
                let mid = existingRoute.count / 2
                excludedEdges.insert("\(existingRoute[mid].stationId)-\(existingRoute[mid+1].stationId)")
                
                if let result = dijkstraPath(from: fromId, to: toId, excludedEdges: excludedEdges, useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) {
                    // 遠回りすぎるルートは除外
                    if result.totalDuration > maxAllowedDuration { continue }
                    
                    let simplePath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
                    let pathHash = simplePath.map { $0.id }.joined(separator: "-")
                    
                    if !usedPaths.contains(pathHash) {
                        usedPaths.insert(pathHash)
                        if let route = buildRouteStops(path: simplePath, fromId: fromId, toId: toId, isPartial: false) {
                            let transfers = route.filter { $0.status == .transfer }.count
                            results.append((route, result.totalDuration, transfers))
                        }
                    }
                }
            }
        }
        
        return selectDiverseRoutes(results, maxRoutes: maxRoutes, transferPenalty: transferPenalty)
    }

    /// スコア（所要時間 + 乗り換えペナルティ）順に選ぶが、既に選んだルートと
    /// 駅の大半が重複する微差ルートは後回しにして、構成の違うルート（並走路線など）を優先する
    private func selectDiverseRoutes(_ results: [(route: [RouteStop], duration: Int, transfers: Int)], maxRoutes: Int, transferPenalty: Int) -> [[RouteStop]] {
        let sorted = results.sorted { ($0.duration + $0.transfers * transferPenalty) < ($1.duration + $1.transfers * transferPenalty) }

        var selected: [(route: [RouteStop], duration: Int, transfers: Int)] = []
        var redundant: [(route: [RouteStop], duration: Int, transfers: Int)] = []
        for candidate in sorted {
            if selected.count >= maxRoutes { break }
            let isMinorVariation = selected.contains { stationOverlapRatio($0.route, candidate.route) > 0.8 }
            if isMinorVariation {
                redundant.append(candidate)
            } else {
                selected.append(candidate)
            }
        }
        // 多様なルートだけでは枠が埋まらなければ微差ルートで補充
        if selected.count < maxRoutes {
            selected.append(contentsOf: redundant.prefix(maxRoutes - selected.count))
        }
        return selected.map { $0.route }
    }

    /// 2ルートの駅の重複率（駅数が少ない方のルート基準）
    private func stationOverlapRatio(_ a: [RouteStop], _ b: [RouteStop]) -> Double {
        let setA = Set(a.map { $0.stationId })
        let setB = Set(b.map { $0.stationId })
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        return Double(intersection) / Double(min(setA.count, setB.count))
    }

    // MARK: - Via Station Route Search
    
    /// 経由駅を通るルート検索（複数ルート対応）
    func findRouteVia(fromId: String, toId: String, viaIds: [String], maxRoutes: Int = 5, useShinkansen: Bool = true, useLimitedExpress: Bool = true) -> [[RouteStop]] {
        var results: [(route: [RouteStop], duration: Int, transfers: Int)] = []
        var usedPaths: Set<String> = []
        
        let transferPenalty = 5
        let allPoints = [fromId] + viaIds + [toId]
        
        for attempt in 0..<(maxRoutes * 3) {
            var excludedEdges: Set<String> = []
            
            // 既存ルートの一部を除外
            if attempt > 0 && !results.isEmpty {
                let lastRoute = results[results.count - 1].route
                if lastRoute.count > 4 {
                    let idx = (attempt % (lastRoute.count - 2)) + 1
                    let edgeKey = "\(lastRoute[idx].stationId)-\(lastRoute[idx+1].stationId)"
                    excludedEdges.insert(edgeKey)
                }
            }
            
            var fullPath: [(id: String, line: String)] = []
            var totalDuration = 0
            var success = true
            
            for i in 0..<(allPoints.count - 1) {
                guard let result = dijkstraPath(from: allPoints[i], to: allPoints[i+1], excludedEdges: excludedEdges, useShinkansen: useShinkansen, useLimitedExpress: useLimitedExpress) else {
                    success = false
                    break
                }
                
                let segmentPath: [(id: String, line: String)] = result.path.map { (id: $0.id, line: $0.line) }
                totalDuration += result.totalDuration
                
                if i == 0 {
                    fullPath = segmentPath
                } else {
                    fullPath.append(contentsOf: segmentPath.dropFirst())
                }
            }
            
            if !success { continue }
            
            let pathHash = fullPath.map { $0.id }.joined(separator: "-")
            if usedPaths.contains(pathHash) { continue }
            usedPaths.insert(pathHash)
            
            if let route = buildRouteStops(path: fullPath, fromId: fromId, toId: toId, isPartial: false) {
                let transfers = route.filter { $0.status == .transfer }.count
                results.append((route, totalDuration, transfers))
            }
            
            if results.count >= maxRoutes { break }
        }
        
        return selectDiverseRoutes(results, maxRoutes: maxRoutes, transferPenalty: transferPenalty)
    }

    // MARK: - Transfer Penalty（乗換コスト）

    /// 直通運転している路線ペア（路線ラベルは変わるが同一列車で乗換不要）
    /// キーは2路線名をソートして "|" で結合したもの
    private static let throughServicePairs: Set<String> = {
        let pairs: [(String, String)] = [
            // 首都圏JR
            ("上野東京ライン", "JR東海道本線(東京～熱海)"),
            ("上野東京ライン", "宇都宮線"),
            ("上野東京ライン", "JR高崎線"),
            ("上野東京ライン", "JR常磐線(上野～取手)"),
            ("JR湘南新宿ライン", "宇都宮線"),
            ("JR湘南新宿ライン", "JR高崎線"),
            ("JR湘南新宿ライン", "JR横須賀線"),
            ("JR湘南新宿ライン", "JR東海道本線(東京～熱海)"),
            ("JR横須賀線", "JR総武快速線"),
            ("JR中央線(快速)", "JR青梅線"),
            ("JR中央線(快速)", "JR中央本線(高尾～塩尻)"),
            ("JR埼京線", "りんかい線"),
            ("JR埼京線", "JR川越線"),
            ("JR埼京線", "相鉄・JR直通線"),
            ("相鉄・JR直通線", "相鉄本線"),
            ("相鉄新横浜線", "相鉄本線"),
            ("JR常磐線(上野～取手)", "JR常磐線(取手～いわき)"),
            // 首都圏メトロ・私鉄
            ("東京メトロ副都心線", "東急東横線"),
            ("東急東横線", "みなとみらい線"),
            ("東京メトロ副都心線", "東武東上線"),
            ("東京メトロ有楽町線", "東武東上線"),
            ("東京メトロ副都心線", "西武有楽町線"),
            ("東京メトロ有楽町線", "西武有楽町線"),
            ("西武有楽町線", "西武池袋線"),
            ("東京メトロ半蔵門線", "東急田園都市線"),
            ("東京メトロ半蔵門線", "東武伊勢崎線"),
            ("東武伊勢崎線", "東武日光線"),
            ("東京メトロ千代田線", "小田急線"),
            ("東京メトロ千代田線", "JR常磐線(上野～取手)"),
            ("東京メトロ日比谷線", "東武伊勢崎線"),
            ("東京メトロ東西線", "JR中央・総武線"),
            ("東京メトロ東西線", "東葉高速線"),
            ("東京メトロ南北線", "東急目黒線"),
            ("都営三田線", "東急目黒線"),
            ("東京メトロ南北線", "埼玉高速鉄道線"),
            ("都営浅草線", "京急本線"),
            ("都営浅草線", "京成押上線"),
            ("京成押上線", "京成本線"),
            ("京急本線", "京急空港線"),
            ("京急本線", "京急久里浜線"),
            ("京急本線", "京急逗子線"),
            ("京王新線", "京王線"),
            ("京王線", "京王相模原線"),
            ("京王線", "京王高尾線"),
            ("小田急線", "小田急江ノ島線"),
            ("小田急線", "小田急多摩線"),
            ("西武池袋線", "西武秩父線"),
            ("京成本線", "北総鉄道北総線"),
            ("京成本線", "芝山鉄道線"),
            // 中京
            ("名鉄名古屋本線", "名鉄犬山線"),
            ("名鉄名古屋本線", "名鉄常滑線"),
            ("名鉄常滑線", "名鉄常滑・空港線"),
            ("近鉄名古屋線", "近鉄大阪線"),
            // 関西JR
            ("JR京都線", "琵琶湖線"),
            ("JR京都線", "JR神戸線(大阪～神戸)"),
            ("JR神戸線(大阪～神戸)", "JR神戸線(神戸～姫路)"),
            ("JR東西線", "学研都市線"),
            ("JR東西線", "JR神戸線(大阪～神戸)"),
            ("JR東西線", "JR宝塚線"),
            ("大阪環状線", "阪和線(天王寺～和歌山)"),
            ("大阪環状線", "JRゆめ咲線"),
            ("阪和線(天王寺～和歌山)", "JR関西空港線"),
            // 関西私鉄
            ("大阪メトロ堺筋線", "阪急千里線"),
            ("阪急千里線", "阪急京都本線"),
            ("北大阪急行電鉄", "大阪メトロ御堂筋線"),
            ("京阪本線", "京阪鴨東線"),
            ("京阪本線", "京阪中之島線"),
            ("近鉄大阪線", "近鉄奈良線"),
            ("近鉄難波線", "近鉄大阪線"),
            ("阪神なんば線", "近鉄難波線"),
            ("阪神なんば線", "阪神本線"),
            ("近鉄京都線", "京都市営地下鉄烏丸線"),
            ("近鉄京都線", "近鉄橿原線"),
            ("近鉄けいはんな線", "大阪メトロ中央線"),
            ("近鉄南大阪線", "近鉄吉野線"),
            // 新幹線
            ("東海道新幹線", "山陽新幹線"),
            ("山陽新幹線", "九州新幹線"),
            ("東北新幹線", "北海道新幹線"),
            ("東北新幹線", "山形新幹線"),
            ("東北新幹線", "秋田新幹線"),
            ("東北新幹線", "上越新幹線"),
            ("東北新幹線", "北陸新幹線"),
            ("上越新幹線", "北陸新幹線"),
            // 九州・東北
            ("福岡市営地下鉄空港線", "JR筑肥線(姪浜～西唐津)"),
            ("仙台空港線", "JR東北本線(黒磯～利府・盛岡)"),
        ]
        return Set(pairs.map { pairKey($0.0, $0.1) })
    }()

    /// 直通が特定の駅でのみ成立するペア（両線が通るが直通はしない駅があるペアのみ登録）
    /// 例: 東西線と総武線は飯田橋でも交差するが、直通運転は中野・西船橋のみ
    private static let throughServiceStationRestrictions: [String: Set<String>] = [
        pairKey("東京メトロ東西線", "JR中央・総武線"): ["中野", "西船橋"],
        pairKey("東京メトロ副都心線", "東武東上線"): ["和光市"],
        pairKey("東京メトロ有楽町線", "東武東上線"): ["和光市"],
        pairKey("近鉄京都線", "京都市営地下鉄烏丸線"): ["竹田"],
        pairKey("東京メトロ千代田線", "JR常磐線(上野～取手)"): ["綾瀬"],
    ]

    private static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// 2路線が直通運転しているか（駅を指定した場合、その駅で直通が成立するかを判定）
    func isThroughService(_ a: String, _ b: String, at stationId: String? = nil) -> Bool {
        let key = Self.pairKey(a, b)
        guard Self.throughServicePairs.contains(key) else { return false }
        if let restriction = Self.throughServiceStationRestrictions[key] {
            guard let stationId, let name = stationById[stationId]?.name else { return false }
            return restriction.contains(name)
        }
        return true
    }

    /// 路線の乗り継ぎにかかる実質コスト（分）
    /// - 同一路線・直通運転・降りて徒歩: 0
    /// - 徒歩から乗車する場合も待ち時間が発生するので通常乗換扱い
    /// - 新幹線がらみの乗換は改札・ホーム移動が長いので重め
    func transferPenalty(from prevLine: String, to nextLine: String, at stationId: String? = nil) -> Int {
        if prevLine.isEmpty || prevLine == nextLine { return 0 }
        if nextLine == "徒歩" { return 0 }
        if isThroughService(prevLine, nextLine, at: stationId) { return 0 }
        if prevLine.contains("新幹線") || nextLine.contains("新幹線") { return 12 }
        return 6
    }

    // MARK: - Private Methods

    /// ダイクストラ法のヒープ（二分ヒープ）
    private struct MinHeap {
        private var items: [(cost: Int, stateKey: String)] = []

        var isEmpty: Bool { items.isEmpty }

        mutating func push(_ item: (cost: Int, stateKey: String)) {
            items.append(item)
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent].cost <= items[i].cost { break }
                items.swapAt(parent, i)
                i = parent
            }
        }

        mutating func pop() -> (cost: Int, stateKey: String)? {
            guard !items.isEmpty else { return nil }
            let top = items[0]
            items[0] = items[items.count - 1]
            items.removeLast()
            var i = 0
            while true {
                let left = i * 2 + 1
                let right = i * 2 + 2
                var smallest = i
                if left < items.count && items[left].cost < items[smallest].cost { smallest = left }
                if right < items.count && items[right].cost < items[smallest].cost { smallest = right }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
            return top
        }
    }

    /// ダイクストラ法で最短時間経路を探索
    /// 状態を「駅 × 乗っている路線」で持ち、乗換ペナルティ込みのコストを最小化する。
    /// 返り値の totalDuration はペナルティを含まない純粋な乗車・徒歩時間。
    private func dijkstraPath(from fromId: String, to toId: String, excludedEdges: Set<String>, useShinkansen: Bool = true, useLimitedExpress: Bool = true) -> (path: [(id: String, line: String, duration: Int)], totalDuration: Int)? {
        guard stationById[fromId] != nil, stationById[toId] != nil else {
            return nil
        }

        // 状態キー: "駅ID|路線名"（路線名は到着時に乗っていた路線、出発駅は空文字）
        let startKey = "\(fromId)|"
        var bestCost: [String: Int] = [startKey: 0]       // 乗換ペナルティ込みコスト
        var rideDuration: [String: Int] = [startKey: 0]   // 純粋な所要時間
        var prevState: [String: (key: String, edgeDuration: Int)] = [:]

        var heap = MinHeap()
        heap.push((cost: 0, stateKey: startKey))

        while let (currentCost, currentKey) = heap.pop() {
            // 既により小さいコストで訪問済みならスキップ（lazy deletion）
            if let best = bestCost[currentKey], best < currentCost {
                continue
            }

            let separatorIndex = currentKey.firstIndex(of: "|")!
            let currentId = String(currentKey[..<separatorIndex])
            let currentLine = String(currentKey[currentKey.index(after: separatorIndex)...])

            // 目的地に到達（ペナルティ込みコスト順に取り出しているので最初の到達が最適）
            if currentId == toId {
                var path: [(id: String, line: String, duration: Int)] = []
                var key = currentKey
                while key != startKey {
                    let sep = key.firstIndex(of: "|")!
                    let stationId = String(key[..<sep])
                    let line = String(key[key.index(after: sep)...])
                    guard let prev = prevState[key] else { break }
                    path.append((stationId, line, prev.edgeDuration))
                    key = prev.key
                }
                path.append((fromId, "", 0))
                path.reverse()
                return (path, rideDuration[currentKey] ?? currentCost)
            }

            if let neighbors = adjacencyList[currentId] {
                for (neighborId, line, duration) in neighbors {
                    // 除外エッジをチェック
                    let edgeKey1 = "\(currentId)-\(neighborId)"
                    let edgeKey2 = "\(neighborId)-\(currentId)"
                    if excludedEdges.contains(edgeKey1) || excludedEdges.contains(edgeKey2) {
                        continue
                    }

                    // 新幹線フィルター
                    if !useShinkansen && line.contains("新幹線") {
                        continue
                    }

                    // 特急フィルター
                    if !useLimitedExpress && (line.contains("特急") || line.contains("エクスプレス") || line.contains("ライナー")) {
                        continue
                    }

                    let newCost = currentCost + duration + transferPenalty(from: currentLine, to: line, at: currentId)
                    let neighborKey = "\(neighborId)|\(line)"

                    if bestCost[neighborKey] == nil || newCost < bestCost[neighborKey]! {
                        bestCost[neighborKey] = newCost
                        rideDuration[neighborKey] = (rideDuration[currentKey] ?? 0) + duration
                        prevState[neighborKey] = (currentKey, duration)
                        heap.push((cost: newCost, stateKey: neighborKey))
                    }
                }
            }
        }

        return nil
    }
    
    /// BFSで経路を探索（所要時間付き）- 互換性のため残す
    private func bfsPath(from fromId: String, to toId: String, excludedEdges: Set<String>, useShinkansen: Bool = true, useLimitedExpress: Bool = true) -> (path: [(id: String, line: String, duration: Int)], totalDuration: Int)? {
        guard stationById[fromId] != nil, stationById[toId] != nil else {
            return nil
        }
        
        var visited = Set<String>()
        var queue: [(id: String, path: [(id: String, line: String, duration: Int)], totalDuration: Int)] = [(fromId, [(fromId, "", 0)], 0)]
        visited.insert(fromId)
        
        while !queue.isEmpty {
            let (currentId, path, totalDuration) = queue.removeFirst()
            
            if currentId == toId {
                return (path, totalDuration)
            }
            
            if let neighbors = adjacencyList[currentId] {
                for (neighborId, line, duration) in neighbors {
                    // 除外エッジをチェック
                    let edgeKey1 = "\(currentId)-\(neighborId)"
                    let edgeKey2 = "\(neighborId)-\(currentId)"
                    if excludedEdges.contains(edgeKey1) || excludedEdges.contains(edgeKey2) {
                        continue
                    }
                    
                    // 新幹線フィルター
                    if !useShinkansen && line.contains("新幹線") {
                        continue
                    }
                    
                    // 特急フィルター
                    if !useLimitedExpress && (line.contains("特急") || line.contains("エクスプレス") || line.contains("ライナー")) {
                        continue
                    }
                    
                    if !visited.contains(neighborId) {
                        visited.insert(neighborId)
                        var newPath = path
                        newPath.append((neighborId, line, duration))
                        queue.append((neighborId, newPath, totalDuration + duration))
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 経路からRouteStopの配列を構築
    private func buildRouteStops(path: [(id: String, line: String)], fromId: String, toId: String, isPartial: Bool) -> [RouteStop]? {
        guard !path.isEmpty else { return nil }
        
        var stops: [RouteStop] = []
        var currentLine: String? = nil
        
        for (index, (stationId, line)) in path.enumerated() {
            guard let station = stationById[stationId] else { continue }
            
            let isFirst = index == 0
            let isLast = index == path.count - 1
            
            // この駅に来るときの路線を更新
            if !line.isEmpty {
                currentLine = line
            }
            
            // 乗り換え検出：次の駅への路線が今と違い、かつ実際に乗換コストが発生する場合
            // （直通運転や降車→徒歩はラベルが変わっても乗換ではない）
            var isTransfer = false
            if !isFirst && !isLast, let current = currentLine {
                let nextLine = path[index + 1].line
                if !nextLine.isEmpty && current != nextLine {
                    isTransfer = transferPenalty(from: current, to: nextLine, at: stationId) > 0
                }
            }
            
            let status: RouteStop.RouteStopStatus
            if isFirst {
                status = .departure
            } else if isLast {
                status = .arrival
            } else if isTransfer {
                status = .transfer
            } else {
                status = .pass
            }
            
            stops.append(RouteStop(
                stationId: station.id,
                stationName: station.name,
                prefecture: station.prefecture,
                latitude: station.latitude,
                longitude: station.longitude,
                status: status,
                line: currentLine,
                alternativeLines: []
            ))
        }

        // 同一路線で連続する乗車区間ごとに、区間全体を通して使える代替路線を計算
        // （各駅の line =「到着時の路線」と同じ基準。区間単位での路線選択に使う）
        if stops.count == path.count {
            var i = 1
            while i < path.count {
                var j = i
                while j + 1 < path.count && path[j + 1].line == path[i].line {
                    j += 1
                }
                // 区間内の全駅間で共通して使える路線の積集合
                var common: Set<String>?
                for k in i...j {
                    let edgeLines = Set(getAlternativeLines(from: path[k - 1].id, to: path[k].id))
                    common = common.map { $0.intersection(edgeLines) } ?? edgeLines
                }
                var alternativeSet = common ?? []

                // 区間の両端駅を単一路線で直接結べる路線も選択肢に加える
                // （経由駅が異なる並走ルート: 飯田橋～西船橋の東西線 vs 総武線など）
                let boardId = path[i - 1].id
                let alightId = path[j].id
                if let board = stationById[boardId], let alight = stationById[alightId] {
                    let candidates = Set(board.lines).intersection(alight.lines).subtracting(alternativeSet)
                    for candidate in candidates where pathAlongLine(candidate, from: boardId, to: alightId) != nil {
                        alternativeSet.insert(candidate)
                    }
                }
                let alternatives = alternativeSet.sorted()
                for k in i...j {
                    stops[k].alternativeLines = alternatives
                }
                i = j + 1
            }

            // 途中駅から分岐して後方の駅で合流できる路線も選択肢に加える
            // （例: 新宿→船橋の総武線ルートで、飯田橋に東西線を出して西船橋まで差し替え可能にする）
            // 通過駅ならその駅自身の選択肢に、乗換駅・出発駅なら「乗換後の区間」（次の駅）の選択肢に入れる
            if path.count >= 4 {
                for p in 0..<(path.count - 2) {
                    guard let station = stationById[path[p].id] else { continue }
                    let isBoundary = path[p].line != path[p + 1].line  // 出発駅・乗換駅
                    let targetIndex = isBoundary ? p + 1 : p
                    var added = false
                    for candidate in station.lines
                    where candidate != path[p].line
                        && candidate != path[p + 1].line
                        && !stops[targetIndex].alternativeLines.contains(candidate) {
                        // 後方の駅のうち、この路線で直接行ける最遠の駅を探す
                        for q in stride(from: path.count - 1, through: p + 2, by: -1) {
                            guard let target = stationById[path[q].id], target.lines.contains(candidate) else { continue }
                            if pathAlongLine(candidate, from: path[p].id, to: path[q].id) != nil {
                                stops[targetIndex].alternativeLines.append(candidate)
                                added = true
                                break
                            }
                        }
                    }
                    if added {
                        stops[targetIndex].alternativeLines.sort()
                    }
                }
            }
        }

        return stops.isEmpty ? nil : stops
    }

    /// 指定路線のエッジだけで2駅間を結ぶ最短経路（駅ID列）。結べない場合はnil
    func pathAlongLine(_ line: String, from fromId: String, to toId: String) -> [String]? {
        guard fromId != toId else { return nil }
        var bestCost: [String: Int] = [fromId: 0]
        var prevStation: [String: String] = [:]
        var heap = MinHeap()
        heap.push((cost: 0, stateKey: fromId))

        while let (currentCost, currentId) = heap.pop() {
            if let best = bestCost[currentId], best < currentCost { continue }
            if currentId == toId {
                var path = [toId]
                var key = toId
                while let prev = prevStation[key] {
                    path.append(prev)
                    key = prev
                }
                return path.reversed()
            }
            for (neighborId, edgeLine, duration) in adjacencyList[currentId] ?? [] where edgeLine == line {
                let newCost = currentCost + duration
                if bestCost[neighborId] == nil || newCost < bestCost[neighborId]! {
                    bestCost[neighborId] = newCost
                    prevStation[neighborId] = currentId
                    heap.push((cost: newCost, stateKey: neighborId))
                }
            }
        }
        return nil
    }

    /// ルート内の stopIndex を含む乗車区間を、指定路線の経路で置き換えたルートを返す
    /// 並走路線（経由駅が異なる場合）は経由駅ごと差し替え、乗換判定・代替路線も再計算される
    func replaceSegmentLine(route: [RouteStop], stopIndex: Int, newLine: String) -> [RouteStop]? {
        guard stopIndex > 0, stopIndex < route.count,
              let oldLine = route[stopIndex].line, oldLine != newLine,
              let firstStop = route.first, let lastStop = route.last else { return nil }

        // 同じ路線で連続する区間の範囲
        var start = stopIndex
        while start > 1, route[start - 1].line == oldLine {
            start -= 1
        }
        var end = stopIndex
        while end + 1 < route.count, route[end + 1].line == oldLine {
            end += 1
        }

        // 1) 区間全体の置き換え：乗車駅（区間の直前の駅）から降車駅まで新路線で結ぶ
        let boardId = route[start - 1].stationId
        let alightId = route[end].stationId
        if let segmentPath = pathAlongLine(newLine, from: boardId, to: alightId) {
            return rebuildRoute(route: route, replaceFrom: start - 1, replaceTo: end,
                                segmentPath: segmentPath, newLine: newLine,
                                fromId: firstStop.stationId, toId: lastStop.stationId)
        }

        // 2) 分岐して後方の駅で合流するケース（例: 飯田橋から東西線で西船橋へ）
        // 起点はタップした駅（通過駅メニュー）→ 区間の乗車駅（乗換後メニュー）の順で試す
        for originIndex in [stopIndex, start - 1] {
            let originId = route[originIndex].stationId
            for q in stride(from: route.count - 1, through: originIndex + 2, by: -1) {
                if let branchPath = pathAlongLine(newLine, from: originId, to: route[q].stationId) {
                    return rebuildRoute(route: route, replaceFrom: originIndex, replaceTo: q,
                                        segmentPath: branchPath, newLine: newLine,
                                        fromId: firstStop.stationId, toId: lastStop.stationId)
                }
            }
        }

        return nil
    }

    /// route の replaceFrom...replaceTo の部分を segmentPath（新路線の駅列）で差し替えて再構築
    private func rebuildRoute(route: [RouteStop], replaceFrom: Int, replaceTo: Int,
                              segmentPath: [String], newLine: String,
                              fromId: String, toId: String) -> [RouteStop]? {
        var newPath: [(id: String, line: String)] = []
        for k in 0...replaceFrom {
            newPath.append((route[k].stationId, route[k].line ?? ""))
        }
        for stationId in segmentPath.dropFirst() {
            newPath.append((stationId, newLine))
        }
        for k in (replaceTo + 1)..<route.count {
            newPath.append((route[k].stationId, route[k].line ?? ""))
        }
        return buildRouteStops(path: newPath, fromId: fromId, toId: toId, isPartial: false)
    }
    
    /// 2つの駅間で使える全ての路線を取得
    func getAlternativeLines(from fromId: String, to toId: String) -> [String] {
        var lines: [String] = []
        
        if let neighbors = adjacencyList[fromId] {
            for (neighborId, line, _) in neighbors {
                if neighborId == toId && !lines.contains(line) {
                    lines.append(line)
                }
            }
        }
        
        return lines
    }
}
