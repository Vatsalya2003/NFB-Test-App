import SwiftUI
import MapKit

/// Tactile map view — renders corridor roads and handles touch/haptic feedback.
struct RouteMapView: UIViewRepresentable {
    let features: [MapFeature]
    let routes: [RouteFeature]
    var isInteractionEnabled: Bool
    var onThreeFingerSwipe: (() -> Void)?

    init(
        features: [MapFeature],
        routes: [RouteFeature] = [],
        isInteractionEnabled: Bool = true,
        onThreeFingerSwipe: (() -> Void)? = nil
    ) {
        self.features = features
        self.routes = routes
        self.isInteractionEnabled = isInteractionEnabled
        self.onThreeFingerSwipe = onThreeFingerSwipe
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.layoutMargins = .zero

        mapView.mapType = .mutedStandard
        mapView.backgroundColor = .white
        mapView.isOpaque = true
        mapView.showsBuildings = false
        mapView.showsTraffic = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isUserInteractionEnabled = isInteractionEnabled
        mapView.pointOfInterestFilter = .excludingAll

        if UIAccessibility.isVoiceOverRunning {
            mapView.isAccessibilityElement = true
            mapView.accessibilityTraits = [.allowsDirectInteraction]
            mapView.accessibilityLabel = "Tactile navigation map"
            mapView.accessibilityHint = "Touch roads for vibration and street names."
        }

        mapView.delegate = context.coordinator

        if onThreeFingerSwipe != nil {
            let swipe = UISwipeGestureRecognizer(
                target: context.coordinator,
                action: #selector(RouteCoordinator.handleThreeFingerSwipe)
            )
            swipe.direction = .right
            swipe.numberOfTouchesRequired = 3
            mapView.addGestureRecognizer(swipe)
        }

        mapView.addOverlay(BlankTileOverlay(), level: .aboveLabels)
        addGestures(to: mapView, coordinator: context.coordinator)

        // Fixed viewport (same as Indoor_Route) — consistent zoom, small background grid
        MapFixedViewport.apply(to: mapView)
        DispatchQueue.main.async {
            MapFixedViewport.apply(to: mapView)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.isUserInteractionEnabled = isInteractionEnabled

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        let corridorFeatures = MapVisibleRectHelper.corridorFeatures(from: features)
        context.coordinator.currentFeatures = corridorFeatures
        context.coordinator.currentRoutes = routes

        corridorFeatures.forEach { $0.addToMap(mapView) }

        MapFixedViewport.apply(to: mapView)
    }

    func makeCoordinator() -> RouteCoordinator {
        RouteCoordinator(self)
    }

    private func addGestures(to mapView: MKMapView, coordinator: RouteCoordinator) {
        let doubleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(RouteCoordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(RouteCoordinator.handleSingleTap(_:))
        )
        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(RouteCoordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.1
        longPress.allowableMovement = 10000
        longPress.require(toFail: doubleTap)

        mapView.addGestureRecognizer(doubleTap)
        mapView.addGestureRecognizer(singleTap)
        mapView.addGestureRecognizer(longPress)
    }
}

// MARK: - Coordinator

class RouteCoordinator: NSObject, MKMapViewDelegate {
    var parent: RouteMapView
    var currentFeatures: [MapFeature] = []
    var currentRoutes: [RouteFeature] = []

    private var activeFeature: MapFeature?
    private var lastUpdateTime: TimeInterval = 0
    private let updateThreshold: TimeInterval = 0.1

    init(_ parent: RouteMapView) {
        self.parent = parent
        super.init()
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is BlankTileOverlay {
            return WhiteTileRenderer(overlay: overlay)
        }

        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = MapRoadStyle.color(for: polyline.title)
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: Gestures

    @objc func handleThreeFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        parent.onThreeFingerSwipe?()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        FeedbackManager.shared.playPulseHaptic()
    }

    @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)

        FeedbackManager.shared.playPulseHaptic()

        if let corridor = corridor(at: point, in: mapView) {
            let name = corridor.properties["name"] as? String ?? "Road"
            FeedbackManager.shared.speak(name)
        }
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)
        let now = CACurrentMediaTime()

        switch gesture.state {
        case .began:
            startFeedback(at: point, in: mapView)
        case .changed:
            if now - lastUpdateTime > updateThreshold {
                lastUpdateTime = now
                updateFeedback(at: point, in: mapView)
            }
        case .ended, .cancelled, .failed:
            stopFeedback()
        default:
            break
        }
    }

    // MARK: Feedback

    private func startFeedback(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.stopAllFeedback()
        let corridor = corridor(at: point, in: mapView)
        activeFeature = corridor

        if corridor != nil {
            FeedbackManager.shared.startContinuousSound()
            if let name = corridor?.properties["name"] as? String {
                FeedbackManager.shared.speak(name)
            }
        }
    }

    private func updateFeedback(at point: CGPoint, in mapView: MKMapView) {
        let corridor = corridor(at: point, in: mapView)
        guard corridor?.id != activeFeature?.id else { return }

        FeedbackManager.shared.stopAllFeedback()
        activeFeature = corridor

        if corridor != nil {
            FeedbackManager.shared.startContinuousSound()
            if let name = corridor?.properties["name"] as? String {
                FeedbackManager.shared.speak(name)
            }
        }
    }

    private func stopFeedback() {
        FeedbackManager.shared.stopAllFeedback()
        activeFeature = nil
    }

    // MARK: Hit Testing

    private func corridor(at point: CGPoint, in mapView: MKMapView) -> CorridorFeature? {
        let threshold = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM) / 2

        for feature in currentFeatures where feature.featureType == "corridor" {
            guard let corridor = feature as? CorridorFeature else { continue }
            for i in 0..<(corridor.coordinates.count - 1) {
                let start = mapView.convert(corridor.coordinates[i], toPointTo: nil)
                let end = mapView.convert(corridor.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return corridor
                }
            }
        }
        return nil
    }

    private func distanceFromPoint(_ point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
