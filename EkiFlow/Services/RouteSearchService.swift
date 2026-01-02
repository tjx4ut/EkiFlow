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
            for connection in connections {
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
    
    /// ルートの所要時間を計算（分）
    func calculateRouteDuration(route: [RouteStop]) -> Int {
        guard route.count > 1 else { return 0 }
        
        var totalDuration = 0
        for i in 0..<(route.count - 1) {
            let fromId = route[i].stationId
            let toId = route[i + 1].stationId
            
            // 隣接リストから所要時間を取得
            if let neighbors = adjacencyList[fromId] {
                if let edge = neighbors.first(where: { $0.neighbor == toId }) {
                    totalDuration += edge.duration
                } else {
                    totalDuration += 3  // デフォルト3分
                }
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
        
        // スコア（所要時間 + 乗り換えペナルティ）でソート
        return results
            .sorted { ($0.duration + $0.transfers * transferPenalty) < ($1.duration + $1.transfers * transferPenalty) }
            .prefix(maxRoutes)
            .map { $0.route }
    }
    
    // MARK: - Via Station Route Search
    
    /// 経由駅を通るルート検索（複数ルート対応）
    func findRouteVia(fromId: String, toId: String, viaIds: [String], maxRoutes: Int = 5) -> [[RouteStop]] {
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
                guard let result = dijkstraPath(from: allPoints[i], to: allPoints[i+1], excludedEdges: excludedEdges) else {
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
        
        return results
            .sorted { ($0.duration + $0.transfers * transferPenalty) < ($1.duration + $1.transfers * transferPenalty) }
            .prefix(maxRoutes)
            .map { $0.route }
    }
    
    // MARK: - Private Methods
    
    /// ダイクストラ法で最短時間経路を探索
    private func dijkstraPath(from fromId: String, to toId: String, excludedEdges: Set<String>, useShinkansen: Bool = true, useLimitedExpress: Bool = true) -> (path: [(id: String, line: String, duration: Int)], totalDuration: Int)? {
        guard stationById[fromId] != nil, stationById[toId] != nil else {
            return nil
        }
        
        // (総所要時間, 現在駅ID, 経路)
        var heap: [(duration: Int, id: String, path: [(id: String, line: String, duration: Int)])] = []
        heap.append((0, fromId, [(fromId, "", 0)]))
        
        var bestDuration: [String: Int] = [:]
        bestDuration[fromId] = 0
        
        while !heap.isEmpty {
            // 最小所要時間のものを取り出す（簡易実装：ソートして先頭を取る）
            heap.sort { $0.duration < $1.duration }
            let (currentDuration, currentId, path) = heap.removeFirst()
            
            // 既により短い経路で訪問済みならスキップ
            if let best = bestDuration[currentId], best < currentDuration {
                continue
            }
            
            if currentId == toId {
                return (path, currentDuration)
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
                    
                    let newDuration = currentDuration + duration
                    
                    // まだ訪問していないか、より短い経路なら追加
                    if bestDuration[neighborId] == nil || newDuration < bestDuration[neighborId]! {
                        bestDuration[neighborId] = newDuration
                        var newPath = path
                        newPath.append((neighborId, line, duration))
                        heap.append((newDuration, neighborId, newPath))
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
            
            // 乗り換え検出：次の駅への路線が今と違う場合、今の駅が乗り換え駅
            var isTransfer = false
            if !isFirst && !isLast && currentLine != nil {
                let nextLine = path[index + 1].line
                if !nextLine.isEmpty && currentLine != nextLine {
                    isTransfer = true
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
            
            // 次の駅への代替路線を取得
            var alternatives: [String] = []
            if !isLast {
                let nextStationId = path[index + 1].id
                alternatives = getAlternativeLines(from: stationId, to: nextStationId)
            }
            
            stops.append(RouteStop(
                stationId: station.id,
                stationName: station.name,
                prefecture: station.prefecture,
                latitude: station.latitude,
                longitude: station.longitude,
                status: status,
                line: currentLine,
                alternativeLines: alternatives
            ))
        }
        
        return stops.isEmpty ? nil : stops
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
