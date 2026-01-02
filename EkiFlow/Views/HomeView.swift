import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var viewModel: StationViewModel
    @Environment(\.modelContext) private var modelContext
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
