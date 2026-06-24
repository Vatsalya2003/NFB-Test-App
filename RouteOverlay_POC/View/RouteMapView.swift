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
    /// When set, only these intersection IDs can zoom into Level 2 detail on double-tap.
    var zoomableIntersectionIDs: Set<String>?
    /// Marriott → JW: rotate 180° so departure is toward the bottom and destination toward the top.
    var rotateMap180: Bool
    var onThreeFingerSwipe: (() -> Void)?
    var onIntersectionDoubleTap: ((IntersectionFeature) -> Void)?

    init(
        features: [MapFeature],
        routes: [RouteFeature] = [],
        isInteractionEnabled: Bool = true,
        zoomableIntersectionIDs: Set<String>? = nil,
        rotateMap180: Bool = false,
        onThreeFingerSwipe: (() -> Void)? = nil,
        onIntersectionDoubleTap: ((IntersectionFeature) -> Void)? = nil
    ) {
        self.features = features
        self.routes = routes
        self.isInteractionEnabled = isInteractionEnabled
        self.zoomableIntersectionIDs = zoomableIntersectionIDs
        self.rotateMap180 = rotateMap180
        self.onThreeFingerSwipe = onThreeFingerSwipe
        self.onIntersectionDoubleTap = onIntersectionDoubleTap
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = AccessibleMapView()
        mapView.touchDelegate = context.coordinator
        mapView.configureAccessibility(
            label: "Tactile navigation map",
            hint: "Enable Direct Touch in VoiceOver, then drag to explore. Double tap a route intersection to zoom in. Do not two-finger swipe on the map."
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

        return mapView
    }

    private func fitViewport(_ mapView: MKMapView) {
        MapVisibleRectHelper.fitContent(mapView, features: features, routes: routes)
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.isUserInteractionEnabled = isInteractionEnabled
        MapOrientation.applyRotation(rotated180: rotateMap180, to: mapView)

        if let accessibleMap = mapView as? AccessibleMapView {
            accessibleMap.onAccessibilityScrollBack = nil
            accessibleMap.onAccessibilityEscape = nil
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

        fitViewport(mapView)
        DispatchQueue.main.async { fitViewport(mapView) }
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
        doubleTap.delaysTouchesBegan = false

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
    private var activeRouteSegmentIndex: Int?
    private var activeFeedbackKey: String = ""
    private var lastUpdateTime: TimeInterval = 0
    private let updateThreshold: TimeInterval = 0.1
    private var fingerIsExploring = false

    init(_ parent: RouteMapView) {
        self.parent = parent
        super.init()
    }

    private func hitTestPoint(_ viewPoint: CGPoint, in mapView: MKMapView) -> CGPoint {
        MapOrientation.hitTestPoint(from: viewPoint, in: mapView, rotated180: parent.rotateMap180)
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
        let view: MKAnnotationView?
        if annotation is IntersectionFeature {
            let reuseID = "intersection"
            view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? IntersectionAnnotationView
                ?? IntersectionAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        } else if annotation is LandmarkFeature {
            let reuseID = "landmark"
            view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? LandmarkAnnotationView
                ?? LandmarkAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        } else if annotation is RouteEndpointFeature {
            let reuseID = "routeEndpoint"
            view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? RouteEndpointAnnotationView
                ?? RouteEndpointAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        } else {
            return nil
        }

        view?.annotation = annotation
        view?.isUserInteractionEnabled = false
        return view
    }

    // MARK: Gestures

    @objc func handleThreeFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        parent.onThreeFingerSwipe?()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let mapView = gesture.view as? MKMapView else { return }
        let point = hitTestPoint(gesture.location(in: mapView), in: mapView)
        performDoubleTap(at: point, in: mapView)
    }

    @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = hitTestPoint(gesture.location(in: mapView), in: mapView)
        performSingleTap(at: point, in: mapView)
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = hitTestPoint(gesture.location(in: mapView), in: mapView)
        let now = CACurrentMediaTime()

        switch gesture.state {
        case .began:
            fingerIsExploring = false
            startFeedback(at: point, in: mapView)
        case .changed:
            fingerIsExploring = true
            if now - lastUpdateTime > updateThreshold {
                lastUpdateTime = now
                updateFeedback(at: point, in: mapView)
            }
        case .ended, .cancelled, .failed:
            fingerIsExploring = false
            stopFeedback()
        default:
            break
        }
    }

    // MARK: AccessibleMapTouchDelegate (VoiceOver direct touch)

    func accessibleMapView(_ mapView: MKMapView, touchBeganAt point: CGPoint) {
        fingerIsExploring = false
        startFeedback(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, touchMovedTo point: CGPoint) {
        fingerIsExploring = true
        let now = CACurrentMediaTime()
        if now - lastUpdateTime > updateThreshold {
            lastUpdateTime = now
            updateFeedback(at: hitTestPoint(point, in: mapView), in: mapView)
        }
    }

    func accessibleMapView(_ mapView: MKMapView, touchEndedAt point: CGPoint) {
        fingerIsExploring = false
        stopFeedback()
    }

    func accessibleMapView(_ mapView: MKMapView, singleTappedAt point: CGPoint) {
        performSingleTap(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, doubleTappedAt point: CGPoint) {
        performDoubleTap(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    private func performSingleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()

        if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature {
            FeedbackManager.shared.speak(endpoint.announcement)
        } else if let landmark = topFeature(at: point, in: mapView) as? LandmarkFeature {
            FeedbackManager.shared.speak(landmark.announcement)
        } else if let intersection = topFeature(at: point, in: mapView) as? IntersectionFeature {
            FeedbackManager.shared.speak(intersection.announcement)
        } else if let route = topFeature(at: point, in: mapView) as? RouteFeature {
            FeedbackManager.shared.speak(route.explorationAnnouncement(forSegmentIndex: activeRouteSegmentIndex ?? 0))
        } else if let feature = topFeature(at: point, in: mapView),
                  let name = feature.properties["name"] as? String {
            FeedbackManager.shared.speak(name)
        }
    }

    private func performDoubleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()

        guard let tappedIntersection = intersection(at: point, in: mapView, forDoubleTap: true) else { return }

        let allowedIDs = routeWaypointIDs()
        if !allowedIDs.isEmpty, !allowedIDs.contains(tappedIntersection.id) {
            FeedbackManager.shared.speak("This intersection is not on your route.")
            return
        }

        FeedbackManager.shared.speak("Opening intersection detail.")
        let openDetail = parent.onIntersectionDoubleTap
        DispatchQueue.main.async {
            openDetail?(tappedIntersection)
        }
    }

    // MARK: Feedback

    private func startFeedback(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.stopAllFeedback()
        let feature = topFeature(at: point, in: mapView)
        activeFeature = feature
        activeFeedbackKey = feedbackKey(for: feature, segmentIndex: activeRouteSegmentIndex)
        beginContinuousFeedback(for: feature)
    }

    private func updateFeedback(at point: CGPoint, in mapView: MKMapView) {
        let feature = topFeature(at: point, in: mapView)
        let key = feedbackKey(for: feature, segmentIndex: activeRouteSegmentIndex)
        guard key != activeFeedbackKey else { return }

        FeedbackManager.shared.stopAllFeedback()
        activeFeature = feature
        activeFeedbackKey = key
        beginContinuousFeedback(for: feature)
    }

    private func feedbackKey(for feature: MapFeature?, segmentIndex: Int?) -> String {
        guard let feature else { return "" }
        if feature is RouteFeature, let segmentIndex {
            return "\(feature.id)_segment_\(segmentIndex)"
        }
        return feature.id
    }

    /// Route endpoints, landmarks, intersections, route line, then streets.
    private func topFeature(at point: CGPoint, in mapView: MKMapView) -> MapFeature? {
        if let endpoint = routeEndpoint(at: point, in: mapView) { return endpoint }
        if let landmark = landmark(at: point, in: mapView) { return landmark }
        if let intersection = intersection(at: point, in: mapView) { return intersection }
        if let hit = routeHit(at: point, in: mapView) {
            activeRouteSegmentIndex = hit.segmentIndex
            return hit.route
        }
        activeRouteSegmentIndex = nil
        return corridor(at: point, in: mapView)
    }

    private func beginContinuousFeedback(for feature: MapFeature?) {
        guard let feature = feature else { return }
        switch feature {
        case let endpoint as RouteEndpointFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            if endpoint.kind == .departure, let route = currentRoutes.first {
                FeedbackManager.shared.speak("\(endpoint.announcement). \(route.routeToDestinationAnnouncement)")
            } else {
                FeedbackManager.shared.speak(endpoint.announcement)
            }
        case let landmark as LandmarkFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            FeedbackManager.shared.speak(landmark.announcement)
        case let intersection as IntersectionFeature:
            FeedbackManager.shared.startContinuousPulsing()
            FeedbackManager.shared.speak(intersection.announcement)
        case let route as RouteFeature:
            FeedbackManager.shared.startRoutePulsing()
            FeedbackManager.shared.speak(route.explorationAnnouncement(forSegmentIndex: activeRouteSegmentIndex ?? 0))
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
        activeRouteSegmentIndex = nil
        activeFeedbackKey = ""
    }

    // MARK: Hit Testing

    /// Waypoints from the loaded route(s); preferred over parent.zoomableIntersectionIDs because
    /// the coordinator's parent can be stale until updateUIView runs.
    private func routeWaypointIDs() -> Set<String> {
        let fromRoutes = Set(currentRoutes.flatMap { $0.waypoints })
        if !fromRoutes.isEmpty { return fromRoutes }
        return parent.zoomableIntersectionIDs ?? []
    }

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

    private func intersection(at point: CGPoint, in mapView: MKMapView, forDoubleTap: Bool = false) -> IntersectionFeature? {
        let half = PhysicalDimensions.mmToPoints(MapIntersectionStyle.sideMM) / 2
        let threshold = forDoubleTap
            ? max(half, 36)   // generous target for deliberate double-tap zoom
            : max(half, 22)
        for feature in currentIntersections {
            let center = mapView.convert(feature.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= threshold {
                return feature
            }
        }
        return nil
    }

    private struct RouteHit {
        let route: RouteFeature
        let segmentIndex: Int
    }

    private func routeHit(at point: CGPoint, in mapView: MKMapView) -> RouteHit? {
        let threshold = max(PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM) / 2, 22)
        var best: (route: RouteFeature, segmentIndex: Int, distance: CGFloat)?

        for route in currentRoutes {
            for i in 0..<(route.coordinates.count - 1) {
                let start = mapView.convert(route.coordinates[i], toPointTo: nil)
                let end = mapView.convert(route.coordinates[i + 1], toPointTo: nil)
                let distance = distanceFromPoint(point, toLineFrom: start, to: end)
                if distance < threshold, best == nil || distance < best!.distance {
                    best = (route, i, distance)
                }
            }
        }

        guard let best else { return nil }
        return RouteHit(route: best.route, segmentIndex: best.segmentIndex)
    }

    private func route(at point: CGPoint, in mapView: MKMapView) -> RouteFeature? {
        routeHit(at: point, in: mapView)?.route
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
