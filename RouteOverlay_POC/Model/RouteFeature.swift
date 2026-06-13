import MapKit

/// Represents a navigation route overlay on top of the tactile map
/// Similar to Google Maps blue walking directions line
class RouteFeature: NSObject, MapFeature, MKOverlay {
    let id: String
    let featureType = "route"
    let properties: [String: Any]
    let coordinates: [CLLocationCoordinate2D]
    
    // Route-specific properties
    let routeName: String
    let totalDistance: Double  // in feet
    let waypoints: [String]    // Ordered list of intersection/landmark IDs
    
    var coordinate: CLLocationCoordinate2D {
        return coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
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
        
        // Extract route-specific properties
        self.routeName = properties["name"] as? String ?? "Route"
        self.totalDistance = properties["distance"] as? Double ?? 0
        self.waypoints = properties["waypoints"] as? [String] ?? []
        
        // Convert coordinates (same format as CorridorFeature)
        self.coordinates = coordinates.map { coord in
            let x = coord[0]
            let y = coord[1]
            return CLLocationCoordinate2D(
                latitude: y / 100000.0,
                longitude: x / 100000.0
            )
        }
        
        super.init()
    }
    
    // MARK: - MapFeature Protocol
    
    @MainActor
    func startHapticFeedback() {
        // Route uses PULSING vibration (differentiated from corridor's continuous)
        FeedbackManager.shared.startRoutePulsing()
    }
    
    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopRoutePulsing()
    }
    
    @MainActor
    func provideFeedback() {
        // Announce route when first touched
        FeedbackManager.shared.speak("Route: \(routeName)")
    }
    
    func addToMap(_ mapView: MKMapView) {
        let polyline = RoutePolyline(coordinates: coordinates, count: coordinates.count)
        polyline.routeId = id
        mapView.addOverlay(polyline, level: .aboveRoads)  // Render above corridors
    }
    
    func removeFromMap(_ mapView: MKMapView) {
        mapView.overlays.forEach { overlay in
            if let routeLine = overlay as? RoutePolyline, routeLine.routeId == id {
                mapView.removeOverlay(routeLine)
            }
        }
    }
}

/// Custom polyline to identify route overlays
class RoutePolyline: MKPolyline {
    var routeId: String = ""
}

// MARK: - Route Presentation Mode

/// Controls how route feedback is presented
enum RoutePresentationMode {
    case mapExploration    // Explore base map (corridors + landmarks)
    case routeNavigation   // Follow route overlay with guidance
    case dualMode          // Both map and route feedback (proof-of-concept default)
}
