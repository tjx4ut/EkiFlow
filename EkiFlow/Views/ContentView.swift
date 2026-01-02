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

// 遅延読み込み用ラッパー（タブが選択されるまでViewを初期化しない）
struct LazyView<Content: View>: View {
    let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content {
        build()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = StationViewModel()
    @StateObject private var tabResetManager = TabResetManager()
    @State private var selectedTab: AppTab = .home

    // 各タブの初期化済みフラグ
    @State private var initializedTabs: Set<AppTab> = [.home]

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            tabContent(for: .search) {
                SearchView()
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }
            .tag(AppTab.search)

            tabContent(for: .log) {
                LogListView()
            }
            .tabItem {
                Label("ログ", systemImage: "list.bullet")
            }
            .tag(AppTab.log)

            tabContent(for: .map) {
                MapView()
            }
            .tabItem {
                Label("マップ", systemImage: "map.fill")
            }
            .tag(AppTab.map)

            tabContent(for: .stats) {
                StatsView()
            }
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

    // タブコンテンツ（未初期化ならローディング表示）
    @ViewBuilder
    private func tabContent<Content: View>(for tab: AppTab, @ViewBuilder content: @escaping () -> Content) -> some View {
        if initializedTabs.contains(tab) {
            content()
        } else {
            // ローディング表示
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("読み込み中...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // 少し遅延させてからViewを初期化（UIの応答性を保つ）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    initializedTabs.insert(tab)
                }
            }
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
