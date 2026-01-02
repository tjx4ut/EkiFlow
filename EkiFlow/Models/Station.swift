import Foundation
import SwiftData
import CoreLocation

@Model
final class Station {
    var id: String
    var name: String
    var prefecture: String
    var latitude: Double
    var longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(id: String, name: String, prefecture: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.prefecture = prefecture
        self.latitude = latitude
        self.longitude = longitude
    }
}
