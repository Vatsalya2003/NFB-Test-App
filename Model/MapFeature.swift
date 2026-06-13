// MapFeature.swift
// Protocol that every map element follows (roads, intersections, landmarks, routes).
// Each type knows how to draw itself on the map and what haptic/speech to play.

import MapKit
import AVFoundation 

protocol MapFeature {
    var id: String { get }
    var featureType: String { get }
    var properties: [String: Any] { get }

    func addToMap(_ mapView: MKMapView)
    func removeFromMap(_ mapView: MKMapView)

    @MainActor func startHapticFeedback()
    @MainActor func stopHapticFeedback()
    @MainActor func provideFeedback()
}
