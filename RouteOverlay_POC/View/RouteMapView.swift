// RouteMapView.swift
// The main tactile map — MapKit + touch gestures + hit testing.
// Renders roads, intersections, landmarks, route line, and yellow start/end dots.

import SwiftUI
import MapKit

/// Tactile map view — renders corridor roads and handles touch/haptic feedback.
struct RouteMapView: UIViewRepresentable {
    let features: [MapFeature]
    let routes: [RouteFeature]
    var isInteractionEnabled: Bool
    var onThreeFingerSwipe: (() -> Void)?
    var onIntersectionDoubleTap: ((IntersectionFeature) -> Void)?

    init(
        features: [MapFeature],
        routes: [RouteFeature] = [],
        isInteractionEnabled: Bool = true,
        onThreeFingerSwipe: (() -> Void)? = nil,
        onIntersectionDoubleTap: ((IntersectionFeature) -> Void)? = nil
    ) {
        self.features = features
        self.routes = routes
        self.isInteractionEnabled = isInteractionEnabled
        self.onThreeFingerSwipe = onThreeFingerSwipe
        self.onIntersectionDoubleTap = onIntersectionDoubleTap
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = AccessibleMapView()
        mapView.onBackGesture = onThreeFingerSwipe
        mapView.touchDelegate = context.coordinator
        mapView.configureAccessibility(
            label: "Tactile navigation map",
            hint: "Touch and drag to explore streets. Double tap an intersection to zoom in."
        )
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

        if let accessibleMap = mapView as? AccessibleMapView {
            accessibleMap.onBackGesture = onThreeFingerSwipe
            accessibleMap.touchDelegate = context.coordinator
        }

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        let corridorFeatures = MapVisibleRectHelper.corridorFeatures(from: features)
        context.coordinator.currentFeatures = corridorFeatures
        context.coordinator.currentRoutes = routes

        corridorFeatures.forEach { $0.addToMap(mapView) }

        // Intersections render as red squares on top of the corridors.
        let intersectionFeatures = features.compactMap { $0 as? IntersectionFeature }
        context.coordinator.currentIntersections = intersectionFeatures
        intersectionFeatures.forEach { $0.addToMap(mapView) }

        // Landmarks render as circles (building markers).
        let landmarkFeatures = features.compactMap { $0 as? LandmarkFeature }
        context.coordinator.currentLandmarks = landmarkFeatures
        landmarkFeatures.forEach { $0.addToMap(mapView) }

        // Route line (#48cae4) drawn above the corridors.
        routes.forEach { $0.addToMap(mapView) }

        // Yellow dots at route start (your location) and end (destination).
        let routeEndpoints = routes.flatMap { RouteEndpointFeature.endpoints(for: $0) }
        context.coordinator.currentRouteEndpoints = routeEndpoints
        routeEndpoints.forEach { $0.addToMap(mapView) }

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

class RouteCoordinator: NSObject, MKMapViewDelegate, AccessibleMapTouchDelegate {
    var parent: RouteMapView
    var currentFeatures: [MapFeature] = []
    var currentIntersections: [IntersectionFeature] = []
    var currentLandmarks: [LandmarkFeature] = []
    var currentRouteEndpoints: [RouteEndpointFeature] = []
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

        // Route line (checked before the generic corridor polyline since RoutePolyline subclasses MKPolyline).
        if let routeLine = overlay as? RoutePolyline {
            let renderer = MKPolylineRenderer(polyline: routeLine)
            renderer.strokeColor = MapRouteStyle.color
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = MapRoadStyle.blue
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is IntersectionFeature {
            let reuseID = "intersection"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? IntersectionAnnotationView
                ?? IntersectionAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        if annotation is LandmarkFeature {
            let reuseID = "landmark"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? LandmarkAnnotationView
                ?? LandmarkAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        if annotation is RouteEndpointFeature {
            let reuseID = "routeEndpoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? RouteEndpointAnnotationView
                ?? RouteEndpointAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        return nil
    }

    // MARK: Gestures

    @objc func handleThreeFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        parent.onThreeFingerSwipe?()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let mapView = gesture.view as? MKMapView else { return }
        performDoubleTap(at: gesture.location(in: mapView), in: mapView)
    }

    @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        performSingleTap(at: gesture.location(in: mapView), in: mapView)
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

    // MARK: AccessibleMapTouchDelegate (VoiceOver direct touch)

    func accessibleMapView(_ mapView: MKMapView, touchBeganAt point: CGPoint) {
        startFeedback(at: point, in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, touchMovedTo point: CGPoint) {
        let now = CACurrentMediaTime()
        if now - lastUpdateTime > updateThreshold {
            lastUpdateTime = now
            updateFeedback(at: point, in: mapView)
        }
    }

    func accessibleMapView(_ mapView: MKMapView, touchEndedAt point: CGPoint) {
        stopFeedback()
    }

    func accessibleMapView(_ mapView: MKMapView, singleTappedAt point: CGPoint) {
        performSingleTap(at: point, in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, doubleTappedAt point: CGPoint) {
        performDoubleTap(at: point, in: mapView)
    }

    private func performSingleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()

        if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature {
            FeedbackManager.shared.speak(endpoint.announcement)
        } else if let landmark = topFeature(at: point, in: mapView) as? LandmarkFeature {
            FeedbackManager.shared.speak(landmark.announcement)
        } else if let feature = topFeature(at: point, in: mapView),
                  let name = feature.properties["name"] as? String {
            FeedbackManager.shared.speak(name)
        }
    }

    private func performDoubleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()
        if let tappedIntersection = intersection(at: point, in: mapView) {
            parent.onIntersectionDoubleTap?(tappedIntersection)
        }
    }

    // MARK: Feedback

    private func startFeedback(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.stopAllFeedback()
        let feature = topFeature(at: point, in: mapView)
        activeFeature = feature
        beginContinuousFeedback(for: feature)
    }

    private func updateFeedback(at point: CGPoint, in mapView: MKMapView) {
        let feature = topFeature(at: point, in: mapView)
        guard feature?.id != activeFeature?.id else { return }

        FeedbackManager.shared.stopAllFeedback()
        activeFeature = feature
        beginContinuousFeedback(for: feature)
    }

    /// Route endpoints, landmarks, intersections, route line, then streets.
    private func topFeature(at point: CGPoint, in mapView: MKMapView) -> MapFeature? {
        if let endpoint = routeEndpoint(at: point, in: mapView) { return endpoint }
        if let landmark = landmark(at: point, in: mapView) { return landmark }
        if let intersection = intersection(at: point, in: mapView) { return intersection }
        if let route = route(at: point, in: mapView) { return route }
        return corridor(at: point, in: mapView)
    }

    private func beginContinuousFeedback(for feature: MapFeature?) {
        guard let feature = feature else { return }
        switch feature {
        case let endpoint as RouteEndpointFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            FeedbackManager.shared.speak(endpoint.announcement)
        case let landmark as LandmarkFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            FeedbackManager.shared.speak(landmark.announcement)
        case is IntersectionFeature:
            FeedbackManager.shared.startContinuousPulsing()
            if let name = feature.properties["name"] as? String {
                FeedbackManager.shared.speak(name)
            }
        case let route as RouteFeature:
            FeedbackManager.shared.startRoutePulsing()
            FeedbackManager.shared.speak("Route: \(route.routeName)")
        default:
            FeedbackManager.shared.startContinuousSound()
            if let name = feature.properties["name"] as? String {
                FeedbackManager.shared.speak(name)
            }
        }
    }

    private func stopFeedback() {
        FeedbackManager.shared.stopAllFeedback()
        activeFeature = nil
    }

    // MARK: Hit Testing

    private func routeEndpoint(at point: CGPoint, in mapView: MKMapView) -> RouteEndpointFeature? {
        let radius = max(PhysicalDimensions.mmToPoints(MapDestinationStyle.diameterMM) / 2, 24)
        for feature in currentRouteEndpoints {
            let center = mapView.convert(feature.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= radius {
                return feature
            }
        }
        return nil
    }

    private func landmark(at point: CGPoint, in mapView: MKMapView) -> LandmarkFeature? {
        // Generous proximity so it fires while a finger traces the route past the building,
        // and also when tapping the offset box itself.
        let anchorThreshold: CGFloat = 30
        let boxThreshold = max(PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxWidthMM) / 2, 22)
        for feature in currentLandmarks {
            let anchor = mapView.convert(feature.coordinate, toPointTo: nil)
            let offset = MapLandmarkStyle.sideOffset(feature.side)
            let box = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
            if hypot(point.x - anchor.x, point.y - anchor.y) <= anchorThreshold
                || hypot(point.x - box.x, point.y - box.y) <= boxThreshold {
                return feature
            }
        }
        return nil
    }

    private func intersection(at point: CGPoint, in mapView: MKMapView) -> IntersectionFeature? {
        let half = PhysicalDimensions.mmToPoints(MapIntersectionStyle.sideMM) / 2
        let threshold = max(half, 22) // ensure an accessible touch target
        for feature in currentIntersections {
            let center = mapView.convert(feature.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= threshold {
                return feature
            }
        }
        return nil
    }

    private func route(at point: CGPoint, in mapView: MKMapView) -> RouteFeature? {
        let threshold = max(PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM) / 2, 22)
        for route in currentRoutes {
            for i in 0..<(route.coordinates.count - 1) {
                let start = mapView.convert(route.coordinates[i], toPointTo: nil)
                let end = mapView.convert(route.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return route
                }
            }
        }
        return nil
    }

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
