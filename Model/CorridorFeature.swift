import MapKit
import SenseKit

class CorridorFeature: NSObject, MapFeature, MKOverlay {
    let id: String
    let featureType = "corridor"
    let properties: [String: Any]
    let coordinates: [CLLocationCoordinate2D]
    
    var coordinate: CLLocationCoordinate2D {
        return coordinates[0]
    }
    
    var boundingMapRect: MKMapRect {
        var mapRect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            let rect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            mapRect = mapRect.union(rect)
        }
        return mapRect
    }
    
    init(id: String, coordinates: [[Double]], properties: [String: Any]) {
        self.id = id
        self.properties = properties
        
        // Coordinates are already stretched by MapDataLoader (same as Indoor_Route).
        // Flip Y so the top-down JSON/designer space matches MapKit's bottom-up
        // latitude (JSON top = screen top).
        self.coordinates = coordinates.map { coord in
            let x = coord[0]
            let y = coord[1]
            return CLLocationCoordinate2D(
                latitude: (MapFixedViewport.verticalFlipSum - y) / 100000.0,
                longitude: x / 100000.0
            )
        }
    }

    @MainActor
    func startHapticFeedback() {
        // Simplified - just call FeedbackManager
        FeedbackManager.shared.startContinuousSound()
    }
    
    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopContinuousSound()
    }
    
    @MainActor
    func provideFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    func addToMap(_ mapView: MKMapView) {
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        polyline.title = id
        mapView.addOverlay(polyline)
    }
    
    func removeFromMap(_ mapView: MKMapView) {
        mapView.overlays.forEach { overlay in
            if let polyline = overlay as? MKPolyline, polyline.title == id {
                mapView.removeOverlay(polyline)
            }
        }
    }
}
