import SwiftUI
import SwiftData

@main
struct EkiFlowApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Station.self,
            StationLog.self,
            Trip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // マイグレーションエラーの場合、既存のデータベースを削除して再作成
            print("⚠️ ModelContainer作成失敗: \(error)")
            print("🗑️ データベースをリセットして再作成します...")
            
            // データベースファイルを削除
            deleteExistingDatabase()
            
            // 再度作成を試行
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("データベースの再作成にも失敗しました: \(error)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    /// 既存のSwiftDataデータベースファイルを削除
    private static func deleteExistingDatabase() {
        let fileManager = FileManager.default
        
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        // SwiftDataのデフォルトストア名
        let storeNames = ["default.store", "default.store-shm", "default.store-wal"]
        
        for storeName in storeNames {
            let storeURL = appSupport.appendingPathComponent(storeName)
            if fileManager.fileExists(atPath: storeURL.path) {
                do {
                    try fileManager.removeItem(at: storeURL)
                    print("✅ 削除成功: \(storeName)")
                } catch {
                    print("❌ 削除失敗: \(storeName) - \(error)")
                }
            }
        }
    }
}
