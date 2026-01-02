import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date?
    var memo: String
    
    init(name: String = "旅程", startDate: Date = Date(), endDate: Date? = nil, memo: String = "") {
        self.id = UUID()
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.memo = memo
    }
}
