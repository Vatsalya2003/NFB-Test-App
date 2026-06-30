// IntersectionFeature.swift
// Red square where two roads meet. Uses IntersectionAnnotationView to draw on map.

import MapKit
import SenseKit

class IntersectionFeature: NSObject, MapFeature, MKAnnotation {
    let id: String
    let featureType = "intersection"
    let properties: [String: Any]
    let coordinate: CLLocationCoordinate2D
    //let radius: CLLocationDistance { return IntersectionFeature.calculatePhysicalRadius() }
    
     var title: String? {
        return properties["name"] as? String ?? "Intersection"
    }

    /// Spoken when exploring, e.g. "4-way intersection of East 1st Street and Brazos Street".
    var announcement: String {
        Self.formatAnnouncement(
            name: properties["name"] as? String,
            ways: properties["ways"] as? Int
        )
    }

    static func formatAnnouncement(name: String?, ways: Int? = nil) -> String {
        let wayCount = ways ?? 4
        let wayLabel = wayCount == 3 ? "3-way" : "4-way"
        guard let name, !name.isEmpty else {
            return "\(wayLabel) intersection"
        }
        let parts = streetNameParts(from: name)
        if parts.count >= 2 {
            return "\(wayLabel) intersection of \(formattedStreetPair(parts))"
        }
        return "\(wayLabel) intersection of \(name)"
    }

    /// Navigation announcement when entering an intersection detail screen.
    static func viewAnnouncement(name: String?) -> String {
        guard let name, !name.isEmpty else {
            return "Intersection view"
        }
        let parts = streetNameParts(from: name)
        if parts.count >= 2 {
            return "Intersection view of \(formattedStreetPair(parts)) streets"
        }
        return "Intersection view of \(name)"
    }

    /// e.g. "East 1st Street, and Brazos Street" — comma adds a brief pause for TTS.
    static func formattedStreetPair(from name: String) -> String {
        let parts = streetNameParts(from: name)
        guard parts.count >= 2 else { return name }
        return formattedStreetPair(parts)
    }

    private static func formattedStreetPair(_ parts: [String]) -> String {
        "\(parts[0]), and \(parts[1])"
    }

    private static func streetNameParts(from name: String) -> [String] {
        let normalized = name.replacingOccurrences(of: " & ", with: " and ")
        return normalized
            .components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }


    init(id: String, coordinates: [Double], properties: [String: Any]) {
        self.id = id
        self.properties = properties
        
        // Coordinates are already stretched by MapDataLoader.
        // Flip Y to match CorridorFeature so intersections land on the roads.
        let x = coordinates[0]
        let y = coordinates[1]
        
        self.coordinate = CLLocationCoordinate2D(
            latitude: (MapFixedViewport.verticalFlipSum - y) / 100000.0,
            longitude: x / 100000.0
        )
        super.init()
    }

    @MainActor
    func startHapticFeedback() {
        // Simplified - just call FeedbackManager
        FeedbackManager.shared.startContinuousPulsing()
    }
    
    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopContinuousPulsing()
    }
    
    @MainActor
    func provideFeedback() {
        FeedbackManager.shared.playPulseHaptic()
        FeedbackManager.shared.speak(announcement)
    }
    
    func addToMap(_ mapView: MKMapView) {
         mapView.addAnnotation(self)
    }
    
    func removeFromMap(_ mapView: MKMapView) {
         mapView.removeAnnotation(self)
    }
}

class IntersectionAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        let sideInPoints = PhysicalDimensions.mmToPoints(MapIntersectionStyle.sideMM)
        
        self.frame = CGRect(x: 0, y: 0, width: sideInPoints, height: sideInPoints)
        self.layer.cornerRadius = 0
        self.backgroundColor = MapIntersectionStyle.red
        
        self.layer.borderWidth = PhysicalDimensions.mmToPoints(0.5)
        self.layer.borderColor = UIColor.white.cgColor
        
        self.centerOffset = CGPoint(x: 0, y: 0)
        self.canShowCallout = false
        // Let touches pass through to the map for hit-testing and double-tap zoom.
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = false
    }
}
