// SidewalkFeature.swift
// Gray sidewalk polyline for Level 2 intersection detail views.
// Same pattern as CorridorFeature but thinner (4mm) and gray.

import MapKit

class SidewalkFeature: NSObject, MapFeature, MKOverlay {
    let id: String
    let featureType = "sidewalk"
    let properties: [String: Any]
    let coordinates: [CLLocationCoordinate2D]
    /// JSON-space coordinates (post-stretch) used to infer north/south/east/west side.
    private let designCoordinates: [[Double]]

    var coordinate: CLLocationCoordinate2D {
        return coordinates[0]
    }

    /// Cardinal side of the intersection, e.g. "North", "East".
    var cardinalDirection: String {
        if let explicit = properties["direction"] as? String ?? properties["side"] as? String,
           !explicit.isEmpty {
            return explicit.prefix(1).uppercased() + explicit.dropFirst().lowercased()
        }
        return Self.inferCardinalDirection(from: designCoordinates)
    }

    /// Spoken label, e.g. "North sidewalk".
    var announcement: String {
        if let phrase = properties["announcement"] as? String, !phrase.isEmpty {
            return phrase
        }
        let dir = cardinalDirection
        return dir.isEmpty ? "Sidewalk" : "\(dir) sidewalk"
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
        self.designCoordinates = coordinates

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
        FeedbackManager.shared.startContinuousSound()
    }

    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopContinuousSound()
    }

    @MainActor
    func provideFeedback() {
        FeedbackManager.shared.playPulseHaptic()
        FeedbackManager.shared.speak(announcement)
    }

    /// Infers north/south/east/west from sidewalk geometry relative to intersection center.
    /// Horizontal segments → north or south side; vertical segments → west or east side.
    static func inferCardinalDirection(
        from coords: [[Double]],
        centerX: Double = 500,
        centerY: Double = 500
    ) -> String {
        guard coords.count >= 2,
              coords[0].count >= 2,
              coords[coords.count - 1].count >= 2 else {
            return ""
        }

        var sumX = 0.0
        var sumY = 0.0
        for coord in coords {
            sumX += coord[0]
            sumY += coord[1]
        }
        let midX = sumX / Double(coords.count)
        let midY = sumY / Double(coords.count)

        let start = coords[0]
        let end = coords[coords.count - 1]
        let dx = abs(end[0] - start[0])
        let dy = abs(end[1] - start[1])

        if dx >= dy {
            return midY < centerY ? "North" : "South"
        }
        return midX < centerX ? "West" : "East"
    }

    func addToMap(_ mapView: MKMapView) {
        let polyline = SidewalkPolyline(coordinates: coordinates, count: coordinates.count)
        polyline.title = id
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    func removeFromMap(_ mapView: MKMapView) {
        mapView.overlays.forEach { overlay in
            if let polyline = overlay as? SidewalkPolyline, polyline.title == id {
                mapView.removeOverlay(polyline)
            }
        }
    }
}

class SidewalkPolyline: MKPolyline {}
