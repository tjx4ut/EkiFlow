import SwiftUI

struct StatsView: View {
    @EnvironmentObject var viewModel: StationViewModel

    var body: some View {
        NavigationStack {
            List {
                // 全体統計
                Section("全体") {
                    HStack {
                        Text("訪問駅数")
                        Spacer()
                        Text("\(viewModel.getTotalStationCount()) / \(viewModel.allStations.count)")
                            .foregroundStyle(.secondary)
                    }

                    let progress = viewModel.allStations.isEmpty ? 0 : Double(viewModel.getTotalStationCount()) / Double(viewModel.allStations.count)
                    ProgressView(value: progress) {
                        Text("制覇率 \(String(format: "%.1f", progress * 100))%")
                            .font(.caption)
                    }
                }

                // ステータス別
                Section("ステータス別") {
                    ForEach(LogStatus.filterableCases, id: \.self) { status in
                        HStack {
                            Text(status.emoji)
                            Text(status.displayName)
                            Spacer()
                            Text("\(viewModel.getStatusCount(status: status))駅")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 都道府県別
                Section("都道府県別") {
                    let prefCounts = viewModel.getPrefectureCount()
                    let sorted = prefCounts.sorted { $0.value > $1.value }

                    if sorted.isEmpty {
                        Text("まだ記録がありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted, id: \.key) { pref, count in
                            NavigationLink {
                                PrefectureStationsView(prefecture: pref)
                            } label: {
                                HStack {
                                    Text(pref)
                                    Spacer()
                                    Text("\(count)駅")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("統計")
        }
    }
}

// MARK: - 都道府県別駅一覧
struct PrefectureStationsView: View {
    @EnvironmentObject var viewModel: StationViewModel
    let prefecture: String

    @State private var stationsWithStatus: [(station: Station, status: LogStatus)] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if stationsWithStatus.isEmpty {
                VStack(spacing: 16) {
                    Text("記録がありません")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(stationsWithStatus, id: \.station.id) { item in
                        NavigationLink {
                            StationDetailView(station: item.station, showCloseButton: false)
                        } label: {
                            HStack {
                                Text(item.status.emoji)
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(item.station.name)
                                    Text(item.status.displayName)
                                        .font(.caption)
                                        .foregroundStyle(item.status.color)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(prefecture)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStations()
        }
    }

    private func loadStations() {
        isLoading = true

        // この都道府県の駅でステータスがある駅を取得
        let prefectureStations = viewModel.allStations.filter { $0.prefecture == prefecture }

        var result: [(station: Station, status: LogStatus)] = []
        for station in prefectureStations {
            if let status = viewModel.getStrongestStatus(for: station.id) {
                result.append((station: station, status: status))
            }
        }

        // ステータスの強さでソート（行った > 乗換 > 通過）
        result.sort { $0.status.strength > $1.status.strength }

        stationsWithStatus = result
        isLoading = false
    }
}

#Preview {
    StatsView()
        .environmentObject(StationViewModel())
}
