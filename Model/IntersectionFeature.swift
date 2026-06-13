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
        let name = properties["name"] as? String ?? "Intersection"
        FeedbackManager.shared.speak(name)
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
    }
}
