import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StationLog.timestamp, order: .reverse) private var recentLogs: [StationLog]
    @State private var showingTripInput = false
    
    // 最寄り駅一覧
    private var homeStations: [Station] {
        viewModel.getHomeStations()
    }
    
    private var isLoading: Bool {
        viewModel.allStations.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("データを読み込み中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // 統計カード
                            HStack(spacing: 16) {
                                StatCard(title: "訪問駅数", value: "\(viewModel.getTotalStationCount())", icon: "mappin.circle.fill", color: .blue)
                                StatCard(title: "全国駅数", value: "\(viewModel.allStations.count)", icon: "tram.fill", color: .green)
                            }
                            .padding(.horizontal)
                            
                            // 旅程入力ボタン
                            Button {
                                showingTripInput = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("旅程を入力")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                            
                            // 最寄り駅セクション
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("最寄り駅")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(homeStations.count)駅登録中")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                                
                                if homeStations.isEmpty {
                                    Text("駅詳細画面から最寄りに追加できます")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(homeStations) { station in
                                                HomeStationChip(station: station)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // 最近のログ
                            VStack(alignment: .leading, spacing: 12) {
                                Text("最近の記録")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                if recentLogs.isEmpty {
                                    Text("まだ記録がありません")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                } else {
                                    ForEach(recentLogs.prefix(10)) { log in
                                        RecentLogRow(log: log, stationName: getStationName(for: log))
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("EkiFlow")
            .sheet(isPresented: $showingTripInput) {
                TripInputView()
            }
        }
    }
    
    /// ログから駅名を取得（複数のソースを試行）
    private func getStationName(for log: StationLog) -> String {
        // 1. ログに保存された駅名を優先使用
        if let name = log.stationName, !name.isEmpty {
            return name
        }
        
        let stationId = log.stationId
        
        // 2. StationViewModelから取得（alt_ids対応済み）
        if let station = viewModel.getStation(byId: stationId) {
            return station.name
        }
        
        // 3. RouteSearchServiceから取得
        if let station = RouteSearchService.shared.getStation(byId: stationId) {
            return station.name
        }
        
        // 4. allStationsから直接ID検索
        if let station = viewModel.allStations.first(where: { $0.id == stationId }) {
            return station.name
        }
        
        // 5. StationDataCacheから検索
        if let stationData = viewModel.getStationData(byId: stationId) {
            return stationData.name
        }
        
        // 取得できない場合は「不明な駅」
        return "不明な駅"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RecentLogRow: View {
    let log: StationLog
    let stationName: String
    
    var body: some View {
        HStack {
            Text(log.status.emoji)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(stationName)
                    .font(.body)
                Text(formatRelativeTime(log.visitDate ?? log.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(log.status.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(log.status.color.opacity(0.2))
                .foregroundStyle(log.status.color)
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    /// 日本語で相対時間を表示
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "たった今"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)時間前"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)日前"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

struct HomeStationChip: View {
    let station: Station
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(Color(red: 0.486, green: 0.714, blue: 0.557))  // 若葉
                .font(.caption)
            Text(station.name)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.486, green: 0.714, blue: 0.557).opacity(0.15))
        .clipShape(Capsule())
    }
}

#Preview {
    HomeView()
        .environmentObject(StationViewModel())
        .modelContainer(for: [Station.self, StationLog.self])
}
