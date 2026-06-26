// RouteFeature.swift
// Cyan navigation route drawn on top of the base map.
// Also defines RouteEndpointFeature (yellow dots) for start/end of route.

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
    let departureName: String?
    let destinationName: String?

    /// Short label while dragging on route segments after the first leg.
    var explorationAnnouncement: String { "Route" }

    /// Start → first intersection: "Route to JW Marriott Downtown" / "Route to Austin Marriott Downtown".
    var routeToDestinationAnnouncement: String {
        "Route to \(Self.spokenRouteDestination(destinationName ?? "your destination"))"
    }

    func explorationAnnouncement(forSegmentIndex segmentIndex: Int) -> String {
        segmentIndex == 0 ? routeToDestinationAnnouncement : explorationAnnouncement
    }

    /// Spoken destination names for route guidance.
    static func spokenRouteDestination(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "JW Marriott Austin": return "JW Marriott Downtown"
        case "Austin Marriott Downtown": return "Austin Marriott Downtown"
        default: return trimmed
        }
    }

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
        self.departureName = properties["departure"] as? String
        self.destinationName = properties["destination"] as? String
        
        // Convert coordinates (same flip + stretch as CorridorFeature so the
        // route lies exactly on the roads).
        self.coordinates = coordinates.map { coord in
            let x = coord[0]
            let y = coord[1]
            return CLLocationCoordinate2D(
                latitude: (MapFixedViewport.verticalFlipSum - y) / 100000.0,
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
        FeedbackManager.shared.speak(explorationAnnouncement)
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

/// Yellow dot at a route start (your location) or end (destination).
class RouteEndpointFeature: NSObject, MapFeature, MKAnnotation {
    enum Kind { case departure, destination }

    /// Spoken at the yellow end dot in Level 2 intersection detail.
    static let intersectionRouteEndAnnouncement =
        "End of route. Double tap to return to map overview."

    /// Spoken at the yellow start dot in Level 2 intersection detail.
    static func intersectionDepartureAnnouncement(intersectionName: String) -> String {
        "Your location at the intersection of \(intersectionName)"
    }

    let id: String
    let featureType = "routeEndpoint"
    let kind: Kind
    let properties: [String: Any]
    let coordinate: CLLocationCoordinate2D
    dynamic var title: String?

    var announcement: String {
        let name = Self.spokenName(properties["name"] as? String ?? "Location")
        switch kind {
        case .departure: return "Your location \(name)"
        case .destination: return "Destination \(name)"
        }
    }

    /// e.g. "JW Marriott Austin" → "JW Marriott Austin hotel"
    private static func spokenName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Location" }
        if trimmed.caseInsensitiveCompare("Route") == .orderedSame { return trimmed }
        if trimmed.lowercased().contains("hotel") { return trimmed }
        return "\(trimmed) hotel"
    }

    init(route: RouteFeature, kind: Kind, name: String) {
        self.kind = kind
        self.id = "\(route.id)_\(kind == .departure ? "departure" : "destination")"
        self.properties = ["name": name]
        self.coordinate = kind == .departure
            ? (route.coordinates.first ?? route.coordinate)
            : (route.coordinates.last ?? route.coordinate)
        self.title = name
        super.init()
    }

    static func endpoints(for route: RouteFeature) -> [RouteEndpointFeature] {
        var result: [RouteEndpointFeature] = []
        if let name = route.departureName {
            result.append(RouteEndpointFeature(route: route, kind: .departure, name: name))
        }
        if let name = route.destinationName {
            result.append(RouteEndpointFeature(route: route, kind: .destination, name: name))
        }
        return result
    }

    @MainActor
    func startHapticFeedback() {
        FeedbackManager.shared.startLandmarkPulsing()
    }

    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopContinuousPulsing()
    }

    @MainActor
    func provideFeedback() {
        FeedbackManager.shared.startLandmarkPulsing()
        FeedbackManager.shared.speak(announcement)
    }

    func addToMap(_ mapView: MKMapView) {
        mapView.addAnnotation(self)
    }

    func removeFromMap(_ mapView: MKMapView) {
        mapView.removeAnnotation(self)
    }
}

/// Orange dot where the route turns in intersection view — ding only, no speech or haptics.
class RouteTurnFeature: NSObject, MapFeature, MKAnnotation {
    let id: String
    let featureType = "routeTurn"
    let properties: [String: Any] = [:]
    let coordinate: CLLocationCoordinate2D
    dynamic var title: String?

    init(id: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.coordinate = coordinate
        self.title = "Route turn"
        super.init()
    }

    /// Interior route vertices where the path changes direction (90° turns at i_1 and i_4).
    static func turns(for route: RouteFeature) -> [RouteTurnFeature] {
        let coords = route.coordinates
        guard coords.count >= 3 else { return [] }

        var turns: [RouteTurnFeature] = []
        for index in 1..<(coords.count - 1) {
            guard isTurnVertex(
                previous: coords[index - 1],
                current: coords[index],
                next: coords[index + 1]
            ) else { continue }
            turns.append(RouteTurnFeature(
                id: "\(route.id)_turn_\(index)",
                coordinate: coords[index]
            ))
        }
        return turns
    }

    private static func isTurnVertex(
        previous: CLLocationCoordinate2D,
        current: CLLocationCoordinate2D,
        next: CLLocationCoordinate2D
    ) -> Bool {
        let dx1 = current.longitude - previous.longitude
        let dy1 = current.latitude - previous.latitude
        let dx2 = next.longitude - current.longitude
        let dy2 = next.latitude - current.latitude
        let cross = dx1 * dy2 - dy1 * dx2
        return abs(cross) > 1e-14
    }

    @MainActor func startHapticFeedback() {}
    @MainActor func stopHapticFeedback() {}
    @MainActor func provideFeedback() {
        FeedbackManager.shared.playRouteTurnDing()
    }

    func addToMap(_ mapView: MKMapView) {
        mapView.addAnnotation(self)
    }

    func removeFromMap(_ mapView: MKMapView) {
        mapView.removeAnnotation(self)
    }
}

/// Orange circle marking a route turn point.
class RouteTurnAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        let diameter = PhysicalDimensions.mmToPoints(MapRouteTurnStyle.diameterMM)
        frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        backgroundColor = MapRouteTurnStyle.color
        layer.cornerRadius = diameter / 2
        layer.borderWidth = PhysicalDimensions.mmToPoints(MapRouteTurnStyle.borderWidthMM)
        layer.borderColor = UIColor.white.cgColor
        centerOffset = .zero
        canShowCallout = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
}

/// Small yellow circle marking a route start or end point.
class RouteEndpointAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        let diameter = PhysicalDimensions.mmToPoints(MapDestinationStyle.diameterMM)
        self.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        self.backgroundColor = MapDestinationStyle.color
        self.layer.cornerRadius = diameter / 2
        self.layer.borderWidth = PhysicalDimensions.mmToPoints(0.4)
        self.layer.borderColor = UIColor.white.cgColor
        self.centerOffset = .zero
        self.canShowCallout = false
        self.isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
}

// MARK: - Route Presentation Mode

/// Controls how route feedback is presented
enum RoutePresentationMode {
    case mapExploration    // Explore base map (corridors + landmarks)
    case routeNavigation   // Follow route overlay with guidance
    case dualMode          // Both map and route feedback (proof-of-concept default)
}
