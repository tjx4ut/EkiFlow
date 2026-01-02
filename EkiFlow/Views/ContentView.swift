import SwiftUI
import SwiftData
import Combine

enum AppTab: Int, CaseIterable {
    case home = 0
    case search = 1
    case log = 2
    case map = 3
    case stats = 4
}

// タブのリセットを管理するクラス
class TabResetManager: ObservableObject {
    @Published var searchResetTrigger = UUID()
    @Published var logResetTrigger = UUID()
    
    func resetSearch() {
        searchResetTrigger = UUID()
    }
    
    func resetLog() {
        logResetTrigger = UUID()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = StationViewModel()
    @StateObject private var tabResetManager = TabResetManager()
    @State private var selectedTab: AppTab = .home
    
    var body: some View {
        TabView(selection: tabSelection) {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }
                .tag(AppTab.home)
            
            SearchView()
                .tabItem {
                    Label("検索", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)
            
            LogListView()
                .tabItem {
                    Label("ログ", systemImage: "list.bullet")
                }
                .tag(AppTab.log)
            
            MapView()
                .tabItem {
                    Label("マップ", systemImage: "map.fill")
                }
                .tag(AppTab.map)
            
            StatsView()
                .tabItem {
                    Label("統計", systemImage: "chart.bar.fill")
                }
                .tag(AppTab.stats)
        }
        .environmentObject(viewModel)
        .environmentObject(tabResetManager)
        .onAppear {
            viewModel.setModelContext(modelContext)
            setupTabBarAppearance()
        }
    }
    
    // タブ選択のバインディング（再タップ検出付き）
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    // 同じタブを再タップ → リセット
                    switch newTab {
                    case .search:
                        tabResetManager.resetSearch()
                    case .log:
                        tabResetManager.resetLog()
                    default:
                        break
                    }
                }
                selectedTab = newTab
            }
        )
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Station.self, StationLog.self, Trip.self])
}
