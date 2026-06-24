// LandmarkFeature.swift
// Building marker — purple tagged box placed beside the road.
// Supports "side" (left/right) and custom announcement text from JSON.

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
        
        // Coordinates are already stretched by MapDataLoader.
        // Flip Y to match CorridorFeature so landmarks land on the roads.
        let x = coordinates[0]
        let y = coordinates[1]
        self.coordinate = CLLocationCoordinate2D(
            latitude: (MapFixedViewport.verticalFlipSum - y) / 100000.0,
            longitude: x / 100000.0
        )
        self.title = properties["name"] as? String
        super.init()
    }

    /// Which side of the road the building sits on ("left"/"right"/"center").
    var side: String {
        properties["side"] as? String ?? "center"
    }

    /// Short label shown inside the box (e.g. "JW").
    var tag: String {
        properties["tag"] as? String ?? ""
    }

    /// Spoken phrase when the landmark is reached, e.g. "JW Marriott on your right".
    /// Uses an explicit "announcement" if provided, otherwise builds one from name + side.
    var announcement: String {
        if let phrase = properties["announcement"] as? String, !phrase.isEmpty {
            return phrase
        }
        let name = properties["name"] as? String ?? "landmark"
        if side != "center" {
            return "\(name) on your \(side)"
        }
        return name
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

/// Landmark marker — a small tagged box placed beside the road to mark a building.
class LandmarkAnnotationView: MKAnnotationView {
    private let tagLabel = UILabel()

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        self.backgroundColor = MapLandmarkStyle.color
        self.layer.cornerRadius = PhysicalDimensions.mmToPoints(MapLandmarkStyle.cornerRadiusMM)
        self.layer.borderWidth = PhysicalDimensions.mmToPoints(MapLandmarkStyle.borderWidthMM)
        self.layer.borderColor = UIColor.white.cgColor
        self.canShowCallout = false
        self.isUserInteractionEnabled = false

        tagLabel.textColor = .white
        tagLabel.textAlignment = .center
        tagLabel.adjustsFontSizeToFitWidth = true
        tagLabel.minimumScaleFactor = 0.5
        tagLabel.font = .systemFont(ofSize: PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxHeightMM) * 0.55,
                                    weight: .bold)
        addSubview(tagLabel)

        configure()
    }

    private func configure() {
        let width = PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxWidthMM)
        let height = PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxHeightMM)
        self.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tagLabel.frame = self.bounds.insetBy(dx: 1, dy: 1)

        guard let landmark = annotation as? LandmarkFeature else { return }
        tagLabel.text = landmark.tag
        // Offset the box to the side of the road; the anchor stays on the road point.
        self.centerOffset = MapLandmarkStyle.sideOffset(landmark.side)
    }
}
