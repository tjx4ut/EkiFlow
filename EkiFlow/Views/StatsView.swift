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
            .navigationTitle("統計")
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(StationViewModel())
}
