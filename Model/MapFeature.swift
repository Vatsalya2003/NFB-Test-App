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
