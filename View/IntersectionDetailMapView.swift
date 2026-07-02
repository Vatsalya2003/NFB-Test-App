// IntersectionDetailMapView.swift
// Level 2 zoomed intersection view — 12 mm roads, 4 mm sidewalks, crosswalks, route on top.
// Based on RouteMapView but with intersection-specific viewport and rendering.

import SwiftUI
import MapKit

struct IntersectionDetailMapView: UIViewRepresentable {
    let features: [MapFeature]
    let routes: [RouteFeature]
    var routeTurns: [RouteTurnFeature] = []
    var intersectionName: String = "Intersection"
    var rotateMap180: Bool = false
    var onBackGesture: (() -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = AccessibleMapView()
        mapView.onAccessibilityScrollBack = onBackGesture
        mapView.onAccessibilityEscape = onBackGesture
        mapView.touchDelegate = context.coordinator
        mapView.configureAccessibility(
            label: "Intersection view",
            hint: "Touch and drag to follow the route. At the yellow end dot you will hear end of route. Double tap anywhere to return to map overview."
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
        mapView.isUserInteractionEnabled = true
        mapView.pointOfInterestFilter = .excludingAll

        mapView.delegate = context.coordinator

        if onBackGesture != nil {
            let swipe = UISwipeGestureRecognizer(
                target: context.coordinator,
                action: #selector(IntersectionDetailCoordinator.handleThreeFingerSwipe)
            )
            swipe.direction = .right
            swipe.numberOfTouchesRequired = 3
            mapView.addGestureRecognizer(swipe)
        }

        mapView.addOverlay(BlankTileOverlay(), level: .aboveLabels)
        addGestures(to: mapView, coordinator: context.coordinator)

        MapIntersectionViewport.apply(to: mapView, edgePadding: MapIntersectionViewport.detailEdgePadding)
        DispatchQueue.main.async {
            MapIntersectionViewport.apply(to: mapView, edgePadding: MapIntersectionViewport.detailEdgePadding)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        MapOrientation.applyRotation(rotated180: rotateMap180, to: mapView)

        if let accessibleMap = mapView as? AccessibleMapView {
            accessibleMap.onAccessibilityScrollBack = onBackGesture
            accessibleMap.onAccessibilityEscape = onBackGesture
            accessibleMap.touchDelegate = context.coordinator
            accessibleMap.configureAccessibility(
                label: "Intersection view",
                hint: "Touch and drag to follow the route. At the yellow end dot you will hear end of route. Double tap anywhere to return to map overview."
            )
        }

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        let mapFeatures = features.filter { $0.featureType != "landmark" }
        let corridors = mapFeatures.filter { $0.featureType == "corridor" }
        let sidewalks = mapFeatures.filter { $0.featureType == "sidewalk" }
        let crosswalks = mapFeatures.filter { $0.featureType == "crosswalk" }

        context.coordinator.currentFeatures = mapFeatures
        context.coordinator.currentIntersections = []
        context.coordinator.currentRoutes = routes
        context.coordinator.currentRouteTurns = routeTurns

        // Roads first, then sidewalks/routes/crosswalks above roads so vertical sidewalks aren't hidden at crossings
        corridors.forEach { $0.addToMap(mapView) }
        sidewalks.forEach { $0.addToMap(mapView) }
        routes.forEach { $0.addToMap(mapView) }
        crosswalks.forEach { $0.addToMap(mapView) }

        let routeEndpoints = routes.flatMap { RouteEndpointFeature.endpoints(for: $0) }
        context.coordinator.currentRouteEndpoints = routeEndpoints
        routeEndpoints.forEach { $0.addToMap(mapView) }
        routeTurns.forEach { $0.addToMap(mapView) }

        MapIntersectionViewport.apply(to: mapView, edgePadding: MapIntersectionViewport.detailEdgePadding)
        DispatchQueue.main.async {
            MapIntersectionViewport.apply(to: mapView, edgePadding: MapIntersectionViewport.detailEdgePadding)
        }
    }

    func makeCoordinator() -> IntersectionDetailCoordinator {
        IntersectionDetailCoordinator(self)
    }

    private func addGestures(to mapView: MKMapView, coordinator: IntersectionDetailCoordinator) {
        let doubleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(IntersectionDetailCoordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(IntersectionDetailCoordinator.handleSingleTap(_:))
        )
        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(IntersectionDetailCoordinator.handleLongPress(_:))
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

class IntersectionDetailCoordinator: NSObject, MKMapViewDelegate, AccessibleMapTouchDelegate {
    var parent: IntersectionDetailMapView
    var currentFeatures: [MapFeature] = []
    var currentIntersections: [IntersectionFeature] = []
    var currentRouteEndpoints: [RouteEndpointFeature] = []
    var currentRouteTurns: [RouteTurnFeature] = []
    var currentRoutes: [RouteFeature] = []

    private var activeFeature: MapFeature?
    private var activeFeedbackKey = ""
    private var announcedDestinationEnd = false
    private var lastUpdateTime: TimeInterval = 0
    private let updateThreshold: TimeInterval = 0.1

    init(_ parent: IntersectionDetailMapView) {
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

        if let routeLine = overlay as? RoutePolyline {
            let renderer = MKPolylineRenderer(polyline: routeLine)
            renderer.strokeColor = MapRouteStyle.color
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        if overlay is SidewalkPolyline {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = MapSidewalkStyle.color
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapSidewalkStyle.lineWidthMM)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        if overlay is CrosswalkPolyline {
            return CrosswalkStripeRenderer(overlay: overlay)
        }

        // Corridors — 12 mm wide in Level 2
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = MapRoadStyle.blue
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapIntersectionDetailStyle.roadLineWidthMM)
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
            view.isAccessibilityElement = false
            return view
        }

        if let endpoint = annotation as? RouteEndpointFeature {
            let reuseID = "routeEndpoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? RouteEndpointAnnotationView
                ?? RouteEndpointAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            view.isAccessibilityElement = false
            return view
        }

        if annotation is RouteTurnFeature {
            let reuseID = "routeTurn"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? RouteTurnAnnotationView
                ?? RouteTurnAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            view.isAccessibilityElement = false
            return view
        }

        return nil
    }

    // MARK: Gestures

    @objc func handleThreeFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        parent.onBackGesture?()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        guard let mapView = gesture.view as? MKMapView else { return }
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
            logTouchEvent(at: point, in: mapView, eventType: .touchDown)
            startFeedback(at: point, in: mapView)
        case .changed:
            if now - lastUpdateTime > updateThreshold {
                lastUpdateTime = now
                logTouchEvent(at: point, in: mapView, eventType: .touchMove)
                updateFeedback(at: point, in: mapView)
            }
        case .ended, .cancelled, .failed:
            logTouchEvent(at: point, in: mapView, eventType: .touchUp)
            speakDestinationEndIfNeeded(at: point, in: mapView)
            stopFeedback()
        default:
            break
        }
    }

    // MARK: AccessibleMapTouchDelegate (VoiceOver direct touch)

    func accessibleMapView(_ mapView: MKMapView, touchBeganAt point: CGPoint) {
        let mapPoint = hitTestPoint(point, in: mapView)
        logTouchEvent(at: mapPoint, in: mapView, eventType: .touchDown)
        startFeedback(at: mapPoint, in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, touchMovedTo point: CGPoint) {
        let now = CACurrentMediaTime()
        let mapPoint = hitTestPoint(point, in: mapView)
        if now - lastUpdateTime > updateThreshold {
            lastUpdateTime = now
            logTouchEvent(at: mapPoint, in: mapView, eventType: .touchMove)
            updateFeedback(at: mapPoint, in: mapView)
        }
    }

    func accessibleMapView(_ mapView: MKMapView, touchEndedAt point: CGPoint) {
        let mapPoint = hitTestPoint(point, in: mapView)
        logTouchEvent(at: mapPoint, in: mapView, eventType: .touchUp)
        speakDestinationEndIfNeeded(at: mapPoint, in: mapView)
        stopFeedback()
    }

    func accessibleMapView(_ mapView: MKMapView, singleTappedAt point: CGPoint) {
        performSingleTap(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, doubleTappedAt point: CGPoint) {
        performDoubleTap(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    private func performSingleTap(at point: CGPoint, in mapView: MKMapView) {
        if routeTurn(at: point, in: mapView) != nil {
            playRouteTurnDingFeedback()
            return
        }

        FeedbackManager.shared.playPulseHaptic()

        if isOnRouteCrosswalk(at: point, in: mapView), let route = route(at: point, in: mapView) {
            FeedbackManager.shared.startRouteOverCrosswalkFeedback()
            FeedbackManager.shared.speak(route.explorationAnnouncement)
        } else if let route = route(at: point, in: mapView) {
            FeedbackManager.shared.speak(route.explorationAnnouncement)
        } else if let crosswalk = crosswalk(at: point, in: mapView) {
            if corridor(at: point, in: mapView) == nil {
                FeedbackManager.shared.stopAllFeedback()
                FeedbackManager.shared.startCrosswalkFeedback()
            }
            let name = crosswalk.properties["name"] as? String ?? "Crosswalk"
            FeedbackManager.shared.speak(name)
        } else if isIntersectionCenterDeadZone(at: point, in: mapView) {
            FeedbackManager.shared.speak("Center")
        } else if isStreetTouch(at: point, in: mapView) {
            speakStreetName(at: point, in: mapView)
        } else if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature,
                  endpoint.kind == .departure {
            FeedbackManager.shared.speak(
                RouteEndpointFeature.intersectionDepartureAnnouncement(intersectionName: parent.intersectionName)
            )
        } else if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature,
                  endpoint.kind == .destination {
            FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
        } else if let feature = topFeature(at: point, in: mapView),
                  let name = feature.properties["name"] as? String {
            FeedbackManager.shared.speak(name)
        }
    }

    private func performDoubleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()
        parent.onBackGesture?()
    }

    // MARK: Feedback

    private func startFeedback(at point: CGPoint, in mapView: MKMapView) {
        announcedDestinationEnd = false

        if let turn = routeTurn(at: point, in: mapView) {
            activeFeature = turn
            activeFeedbackKey = turn.id
            playRouteTurnDingFeedback()
            return
        }

        FeedbackManager.shared.stopAllFeedback()

        if isIntersectionCenterDeadZone(at: point, in: mapView) {
            activeFeature = nil
            activeFeedbackKey = "intersection_center"
            FeedbackManager.shared.startHeavyBuzzFeedback()
            FeedbackManager.shared.speak("Center")
            return
        }

        let feature = topFeature(at: point, in: mapView)
        activeFeature = feature
        activeFeedbackKey = feedbackKey(for: feature, at: point, in: mapView)
        beginContinuousFeedback(for: feature, at: point, in: mapView)
    }

    private func feedbackKey(for feature: MapFeature?, at point: CGPoint, in mapView: MKMapView) -> String {
        guard let feature else { return "" }
        if let route = feature as? RouteFeature, isOnRouteCrosswalk(at: point, in: mapView) {
            return routeCrosswalkFeedbackKey(for: route)
        }
        return feature.id
    }

    private func updateFeedback(at point: CGPoint, in mapView: MKMapView) {
        if let turn = routeTurn(at: point, in: mapView) {
            let enteringTurn = activeFeature?.id != turn.id
            activeFeature = turn
            if enteringTurn {
                playRouteTurnDingFeedback()
            }
            return
        }

        if activeFeature is RouteTurnFeature {
            FeedbackManager.shared.stopRouteTurnFeedback()
            activeFeature = nil
        }

        if isIntersectionCenterDeadZone(at: point, in: mapView) {
            let key = "intersection_center"
            if activeFeedbackKey != key {
                FeedbackManager.shared.stopAllFeedback()
                activeFeedbackKey = key
                activeFeature = nil
                FeedbackManager.shared.startHeavyBuzzFeedback()
                FeedbackManager.shared.speak("Center")
            }
            return
        }

        if isOnRouteCrosswalk(at: point, in: mapView), let route = route(at: point, in: mapView) {
            let key = routeCrosswalkFeedbackKey(for: route)
            if activeFeedbackKey != key {
                FeedbackManager.shared.stopAllFeedback()
                activeFeedbackKey = key
                activeFeature = route
                FeedbackManager.shared.speak(route.explorationAnnouncement)
            }
            FeedbackManager.shared.startRouteOverCrosswalkFeedback()
            return
        }

        if let route = route(at: point, in: mapView) {
            let key = route.id
            if activeFeedbackKey != key {
                FeedbackManager.shared.stopAllFeedback()
                activeFeedbackKey = key
                activeFeature = route
                FeedbackManager.shared.startRoutePulsing()
                FeedbackManager.shared.speak(route.explorationAnnouncement)
            }
            return
        }

        if let crosswalk = crosswalk(at: point, in: mapView) {
            let key = crosswalk.id
            let onCorridor = corridor(at: point, in: mapView) != nil
            if activeFeedbackKey != key {
                FeedbackManager.shared.stopAllFeedback()
                activeFeedbackKey = key
                activeFeature = crosswalk
                if onCorridor {
                    FeedbackManager.shared.startStreetOverCrosswalkFeedback()
                } else {
                    FeedbackManager.shared.startCrosswalkFeedback()
                }
            } else if onCorridor, !FeedbackManager.shared.isPlayingContinuousSound {
                FeedbackManager.shared.startStreetOverCrosswalkFeedback()
            } else if !onCorridor, !FeedbackManager.shared.isCrosswalkPulsing {
                FeedbackManager.shared.startCrosswalkFeedback()
            }
            return
        }

        let feature = topFeature(at: point, in: mapView)
        let key = feature?.id ?? ""
        guard key != activeFeedbackKey else { return }

        FeedbackManager.shared.stopAllFeedback()
        activeFeedbackKey = key
        activeFeature = feature
        beginContinuousFeedback(for: feature, at: point, in: mapView)
    }

    private func isOnRouteCrosswalk(at point: CGPoint, in mapView: MKMapView) -> Bool {
        route(at: point, in: mapView) != nil && crosswalk(at: point, in: mapView) != nil
    }

    private func routeCrosswalkFeedbackKey(for route: RouteFeature) -> String {
        "\(route.id)_on_crosswalk"
    }

    private func topFeature(at point: CGPoint, in mapView: MKMapView) -> MapFeature? {
        if let endpoint = routeEndpoint(at: point, in: mapView) { return endpoint }
        if let route = route(at: point, in: mapView) { return route }
        if let crosswalk = crosswalk(at: point, in: mapView) { return crosswalk }
        if isIntersectionCenterDeadZone(at: point, in: mapView) { return nil }
        if let sidewalk = sidewalk(at: point, in: mapView) { return sidewalk }
        if let corridor = corridor(at: point, in: mapView) { return corridor }
        return nil
    }

    private func beginContinuousFeedback(for feature: MapFeature?, at point: CGPoint, in mapView: MKMapView) {
        guard let feature = feature else { return }
        switch feature {
        case let endpoint as RouteEndpointFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            if endpoint.kind == .destination {
                announcedDestinationEnd = true
                FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
            } else if endpoint.kind == .departure {
                FeedbackManager.shared.speak(
                    RouteEndpointFeature.intersectionDepartureAnnouncement(intersectionName: parent.intersectionName)
                )
            } else {
                FeedbackManager.shared.speak(endpoint.announcement)
            }
        case is CrosswalkFeature:
            if corridor(at: point, in: mapView) != nil {
                FeedbackManager.shared.startStreetOverCrosswalkFeedback()
            } else {
                FeedbackManager.shared.startCrosswalkFeedback()
            }
            if let crosswalk = feature as? CrosswalkFeature,
               let name = crosswalk.properties["name"] as? String {
                FeedbackManager.shared.speak(name)
            } else {
                FeedbackManager.shared.speak("Crosswalk")
            }
        case let route as RouteFeature:
            if isOnRouteCrosswalk(at: point, in: mapView) {
                FeedbackManager.shared.startRouteOverCrosswalkFeedback()
            } else {
                FeedbackManager.shared.startRoutePulsing()
            }
            FeedbackManager.shared.speak(route.explorationAnnouncement)
        case is SidewalkFeature:
            applySidewalkFeedback(at: point, in: mapView)
        case is CorridorFeature:
            applyRoadFeedback(at: point, in: mapView)
        default:
            applyRoadFeedback(at: point, in: mapView)
        }
    }

    private func applyRoadFeedback(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.startHeavyBuzzFeedback()
        speakStreetName(at: point, in: mapView)
    }

    private func applySidewalkFeedback(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.startStreetFeedback()
        if let sidewalk = sidewalk(at: point, in: mapView) {
            FeedbackManager.shared.speak(sidewalk.announcement)
        } else {
            FeedbackManager.shared.speak("Sidewalk")
        }
    }

    private func isStreetTouch(at point: CGPoint, in mapView: MKMapView) -> Bool {
        sidewalk(at: point, in: mapView) != nil || corridor(at: point, in: mapView) != nil
    }

    private func speakStreetName(at point: CGPoint, in mapView: MKMapView) {
        if let name = streetName(at: point, in: mapView) {
            FeedbackManager.shared.speak(name)
        }
    }

    private func streetName(at point: CGPoint, in mapView: MKMapView) -> String? {
        if let corridor = corridor(at: point, in: mapView),
           let name = corridor.properties["name"] as? String {
            return name
        }
        let roadHalf = PhysicalDimensions.mmToPoints(MapIntersectionDetailStyle.roadLineWidthMM) / 2
        let lookupDistance = roadHalf + PhysicalDimensions.mmToPoints(14)
        if let corridor = nearestCorridor(to: point, in: mapView, maxDistance: lookupDistance),
           let name = corridor.properties["name"] as? String {
            return name
        }
        return nil
    }

    private func nearestCorridor(
        to point: CGPoint,
        in mapView: MKMapView,
        maxDistance: CGFloat
    ) -> CorridorFeature? {
        var closest: (corridor: CorridorFeature, distance: CGFloat)?
        for feature in currentFeatures where feature.featureType == "corridor" {
            guard let corridor = feature as? CorridorFeature else { continue }
            for i in 0..<(corridor.coordinates.count - 1) {
                let start = mapView.convert(corridor.coordinates[i], toPointTo: nil)
                let end = mapView.convert(corridor.coordinates[i + 1], toPointTo: nil)
                let distance = distanceFromPoint(point, toLineFrom: start, to: end)
                if distance <= maxDistance {
                    if closest == nil || distance < closest!.distance {
                        closest = (corridor, distance)
                    }
                }
            }
        }
        return closest?.corridor
    }

    private func stopFeedback() {
        FeedbackManager.shared.stopAllFeedback()
        activeFeature = nil
        activeFeedbackKey = ""
        announcedDestinationEnd = false
    }

    private func speakDestinationEndIfNeeded(at point: CGPoint, in mapView: MKMapView) {
        guard !announcedDestinationEnd,
              let endpoint = routeEndpoint(at: point, in: mapView),
              endpoint.kind == .destination else { return }
        FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
    }

    private func playRouteTurnDingFeedback() {
        FeedbackManager.shared.startRouteTurnFeedback()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: "Route turn")
        }
    }

    private func isOnRouteTurnDot(at point: CGPoint, in mapView: MKMapView) -> Bool {
        routeTurn(at: point, in: mapView) != nil
    }

    // MARK: Hit Testing

    private func routeTurn(at point: CGPoint, in mapView: MKMapView) -> RouteTurnFeature? {
        let dotRadius = MapRouteTurnStyle.hitRadiusPoints
        for turn in currentRouteTurns {
            let center = mapView.convert(turn.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= dotRadius {
                return turn
            }
        }
        return nil
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

    private func isIntersectionCenterDeadZone(at point: CGPoint, in mapView: MKMapView) -> Bool {
        let center = mapView.convert(
            CLLocationCoordinate2D(
                latitude: (MapFixedViewport.verticalFlipSum - MapIntersectionLayout.center) / 100_000.0,
                longitude: MapIntersectionLayout.center / 100_000.0
            ),
            toPointTo: nil
        )
        let half = PhysicalDimensions.mmToPoints(MapIntersectionDetailStyle.roadLineWidthMM) / 2
        return abs(point.x - center.x) <= half && abs(point.y - center.y) <= half
    }

    private func crosswalk(at point: CGPoint, in mapView: MKMapView) -> CrosswalkFeature? {
        if isOnRouteTurnDot(at: point, in: mapView) { return nil }
        let threshold = max(PhysicalDimensions.mmToPoints(MapCrosswalkStyle.lineWidthMM) / 2, 34)
        for feature in currentFeatures where feature.featureType == "crosswalk" {
            guard let cw = feature as? CrosswalkFeature else { continue }
            for i in 0..<(cw.coordinates.count - 1) {
                let start = mapView.convert(cw.coordinates[i], toPointTo: nil)
                let end = mapView.convert(cw.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return cw
                }
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
        let threshold = PhysicalDimensions.mmToPoints(MapIntersectionDetailStyle.roadLineWidthMM) / 2
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

    private func sidewalk(at point: CGPoint, in mapView: MKMapView) -> SidewalkFeature? {
        let threshold = PhysicalDimensions.mmToPoints(MapSidewalkStyle.lineWidthMM) / 2
        for feature in currentFeatures where feature.featureType == "sidewalk" {
            guard let sw = feature as? SidewalkFeature else { continue }
            for i in 0..<(sw.coordinates.count - 1) {
                let start = mapView.convert(sw.coordinates[i], toPointTo: nil)
                let end = mapView.convert(sw.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return sw
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

    private func logTouchEvent(at point: CGPoint, in mapView: MKMapView, eventType: TouchEventType) {
        guard DataService.shared.isSessionActive else { return }
        Task { @MainActor in
            DataService.shared.logTouchEvent(
                at: point,
                in: mapView,
                eventType: eventType,
                context: .intersectionDetail,
                features: currentFeatures,
                routes: currentRoutes,
                routeEndpoints: currentRouteEndpoints,
                routeTurns: currentRouteTurns
            )
        }
    }
}
