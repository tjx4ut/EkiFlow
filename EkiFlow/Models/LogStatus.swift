import Foundation
import SwiftUI

enum LogStatus: String, Codable, CaseIterable {
    case visited = "visited"
    case transferred = "transferred"
    case passed = "passed"
    case home = "home"
    case homeRemoved = "homeRemoved"  // 最寄り駅から外した（履歴用）
    
    var displayName: String {
        switch self {
        case .visited: return "行った"
        case .transferred: return "乗換"
        case .passed: return "通過"
        case .home: return "最寄り"
        case .homeRemoved: return "元最寄り"
        }
    }
    
    var emoji: String {
        switch self {
        case .visited: return "🌸"
        case .transferred: return "🌷"
        case .passed: return "🌿"
        case .home: return "🏠"
        case .homeRemoved: return "🏚️"
        }
    }
    
    /// 桜カラーテーマ
    var color: Color {
        switch self {
        case .visited: return Color(red: 0.973, green: 0.647, blue: 0.761)      // #F8A5C2 桜ピンク
        case .transferred: return Color(red: 0.980, green: 0.855, blue: 0.867)  // #FADADD 薄桜
        case .passed: return Color(red: 0.545, green: 0.451, blue: 0.333)       // #8B7355 幹茶
        case .home: return Color(red: 0.486, green: 0.714, blue: 0.557)         // #7CB68E 若葉
        case .homeRemoved: return Color(red: 0.545, green: 0.451, blue: 0.333)  // #8B7355 幹茶（通過と同じ）
        }
    }
    
    /// ステータスの強さ（home > visited > transferred > passed）
    var strength: Int {
        switch self {
        case .home: return 4
        case .visited: return 3
        case .transferred: return 2
        case .passed: return 1
        case .homeRemoved: return 0  // 最も弱い（実質的には無効）
        }
    }
    
    /// フィルター表示用のケース（homeRemovedを除く）
    static var filterableCases: [LogStatus] {
        return [.visited, .transferred, .passed, .home]
    }
}
