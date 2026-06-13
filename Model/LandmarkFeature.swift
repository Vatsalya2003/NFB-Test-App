import MapKit
import SenseKit


enum LandmarkPresentationMode {
    case practiceNL           // Practice with Natural Language
    case practiceSpatial      // Practice with Spatialized Audio
    case practiceIcons        // Practice with Auditory Icons
    case naturalLanguage      // Condition 1: "Bathroom is on your left"
    case spatializedAudio    // Condition 2: "Bathroom" from left speaker
    case spatializedIcons    // Condition 3: Toilet flush from left speaker
}

class LandmarkFeature: NSObject, MapFeature, MKAnnotation {
    let id: String
    let featureType = "landmark"
    let properties: [String: Any]
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    
    init(id: String, coordinates: [Double], properties: [String: Any]) {
        self.id = id
        self.properties = properties
        
        // Coordinates are already stretched by MapDataLoader; Y-flip so JSON top = screen top
        let x = coordinates[0]
        let y = coordinates[1]
        let boundsHeight = 1000.0
        self.coordinate = CLLocationCoordinate2D(
            latitude: (boundsHeight - y) / 100000.0,
            longitude: x / 100000.0
        )
        self.title = properties["name"] as? String
        super.init()
    }

    
   @MainActor
    func startHapticFeedback() {
        // Use fast pulsing for landmarks (2x faster than intersections)
        FeedbackManager.shared.startLandmarkPulsing()
    }
    
    @MainActor
    func stopHapticFeedback() {
        FeedbackManager.shared.stopContinuousPulsing()
    }
    
    @MainActor
    func provideFeedback() {
        FeedbackManager.shared.provideLandmarkFeedback(self)
    }
    
    func addToMap(_ mapView: MKMapView) {
        mapView.addAnnotation(self)
    }
    
    func removeFromMap(_ mapView: MKMapView) {
        mapView.removeAnnotation(self)
    }
}
