// IntersectionDetailMapView.swift
// Level 2 zoomed intersection view — 12 mm roads, 4 mm sidewalks, crosswalks, route on top.
// Based on RouteMapView but with intersection-specific viewport and rendering.

import SwiftUI
import MapKit

struct IntersectionDetailMapView: UIViewRepresentable {
    let features: [MapFeature]
    let routes: [RouteFeature]
    var intersectionName: String = "Intersection"
    var rotateMap180: Bool = false
    var onBackGesture: (() -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = AccessibleMapView()
        mapView.onAccessibilityScrollBack = onBackGesture
        mapView.onAccessibilityEscape = onBackGesture
        mapView.touchDelegate = context.coordinator
        mapView.configureAccessibility(
            label: "Intersection detail map",
            hint: "Touch and drag to follow the route. At the yellow end dot you will hear end of route. Double tap the end dot to return to map overview."
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
        }

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        let corridors = features.filter { $0.featureType == "corridor" }
        let sidewalks = features.filter { $0.featureType == "sidewalk" }
        let crosswalks = features.filter { $0.featureType == "crosswalk" }
        let intersections = features.compactMap { $0 as? IntersectionFeature }
        let landmarks = features.compactMap { $0 as? LandmarkFeature }

        context.coordinator.currentFeatures = features
        context.coordinator.currentIntersections = intersections
        context.coordinator.currentLandmarks = landmarks
        context.coordinator.currentRoutes = routes

        // Roads first, then sidewalks/routes/crosswalks above roads so vertical sidewalks aren't hidden at crossings
        corridors.forEach { $0.addToMap(mapView) }
        sidewalks.forEach { $0.addToMap(mapView) }
        routes.forEach { $0.addToMap(mapView) }
        crosswalks.forEach { $0.addToMap(mapView) }
        intersections.forEach { $0.addToMap(mapView) }
        landmarks.forEach { $0.addToMap(mapView) }

        let routeEndpoints = routes.flatMap { RouteEndpointFeature.endpoints(for: $0) }
        context.coordinator.currentRouteEndpoints = routeEndpoints
        routeEndpoints.forEach { $0.addToMap(mapView) }

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
    var currentLandmarks: [LandmarkFeature] = []
    var currentRouteEndpoints: [RouteEndpointFeature] = []
    var currentRoutes: [RouteFeature] = []

    private var activeFeature: MapFeature?
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
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = MapCrosswalkStyle.color
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapCrosswalkStyle.lineWidthMM)
            renderer.lineDashPattern = MapCrosswalkStyle.dashPattern
            renderer.lineCap = .butt
            return renderer
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
            return view
        }

        if annotation is LandmarkFeature {
            let reuseID = "landmark"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? LandmarkAnnotationView
                ?? LandmarkAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        if let endpoint = annotation as? RouteEndpointFeature {
            let reuseID = "routeEndpoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? RouteEndpointAnnotationView
                ?? RouteEndpointAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            if endpoint.kind == .destination {
                view.isAccessibilityElement = true
                view.accessibilityLabel = RouteEndpointFeature.intersectionRouteEndAnnouncement
                view.accessibilityHint = "Double tap to return to map overview"
            } else if endpoint.kind == .departure {
                view.isAccessibilityElement = true
                view.accessibilityLabel = RouteEndpointFeature.intersectionDepartureAnnouncement(
                    intersectionName: parent.intersectionName
                )
                view.accessibilityHint = "Starting point at this intersection"
            }
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
            startFeedback(at: point, in: mapView)
        case .changed:
            if now - lastUpdateTime > updateThreshold {
                lastUpdateTime = now
                updateFeedback(at: point, in: mapView)
            }
        case .ended, .cancelled, .failed:
            if let endpoint = routeEndpoint(at: point, in: mapView), endpoint.kind == .destination {
                FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
            }
            stopFeedback()
        default:
            break
        }
    }

    // MARK: AccessibleMapTouchDelegate (VoiceOver direct touch)

    func accessibleMapView(_ mapView: MKMapView, touchBeganAt point: CGPoint) {
        startFeedback(at: hitTestPoint(point, in: mapView), in: mapView)
    }

    func accessibleMapView(_ mapView: MKMapView, touchMovedTo point: CGPoint) {
        let now = CACurrentMediaTime()
        if now - lastUpdateTime > updateThreshold {
            lastUpdateTime = now
            updateFeedback(at: hitTestPoint(point, in: mapView), in: mapView)
        }
    }

    func accessibleMapView(_ mapView: MKMapView, touchEndedAt point: CGPoint) {
        let mapPoint = hitTestPoint(point, in: mapView)
        if let endpoint = routeEndpoint(at: mapPoint, in: mapView), endpoint.kind == .destination {
            FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
        }
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

        if let sidewalk = topFeature(at: point, in: mapView) as? SidewalkFeature {
            FeedbackManager.shared.speak(sidewalk.announcement)
        } else if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature,
                  endpoint.kind == .departure {
            FeedbackManager.shared.speak(
                RouteEndpointFeature.intersectionDepartureAnnouncement(intersectionName: parent.intersectionName)
            )
        } else if let endpoint = topFeature(at: point, in: mapView) as? RouteEndpointFeature,
                  endpoint.kind == .destination {
            FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
        } else if let intersection = topFeature(at: point, in: mapView) as? IntersectionFeature {
            FeedbackManager.shared.speak(intersection.announcement)
        } else if let route = topFeature(at: point, in: mapView) as? RouteFeature {
            FeedbackManager.shared.speak(route.explorationAnnouncement)
        } else if let feature = topFeature(at: point, in: mapView),
                  let name = feature.properties["name"] as? String {
            FeedbackManager.shared.speak(name)
        }
    }

    private func performDoubleTap(at point: CGPoint, in mapView: MKMapView) {
        FeedbackManager.shared.playPulseHaptic()

        if let endpoint = routeEndpoint(at: point, in: mapView), endpoint.kind == .destination {
            FeedbackManager.shared.speak("Returning to map overview")
            parent.onBackGesture?()
            return
        }

        parent.onBackGesture?()
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

    private func topFeature(at point: CGPoint, in mapView: MKMapView) -> MapFeature? {
        if let endpoint = routeEndpoint(at: point, in: mapView) { return endpoint }
        if let landmark = landmark(at: point, in: mapView) { return landmark }
        if let intersection = intersection(at: point, in: mapView) { return intersection }
        if let crosswalk = crosswalk(at: point, in: mapView) { return crosswalk }
        if let route = route(at: point, in: mapView) { return route }
        if let corridor = corridor(at: point, in: mapView) { return corridor }
        if let sidewalk = sidewalk(at: point, in: mapView) { return sidewalk }
        return nil
    }

    private func beginContinuousFeedback(for feature: MapFeature?) {
        guard let feature = feature else { return }
        switch feature {
        case let endpoint as RouteEndpointFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            if endpoint.kind == .destination {
                FeedbackManager.shared.speak(RouteEndpointFeature.intersectionRouteEndAnnouncement)
            } else if endpoint.kind == .departure {
                FeedbackManager.shared.speak(
                    RouteEndpointFeature.intersectionDepartureAnnouncement(intersectionName: parent.intersectionName)
                )
            } else {
                FeedbackManager.shared.speak(endpoint.announcement)
            }
        case let landmark as LandmarkFeature:
            FeedbackManager.shared.startLandmarkPulsing()
            FeedbackManager.shared.speak(landmark.announcement)
        case let intersection as IntersectionFeature:
            FeedbackManager.shared.startContinuousPulsing()
            FeedbackManager.shared.speak(intersection.announcement)
        case is CrosswalkFeature:
            FeedbackManager.shared.startContinuousPulsing()
            FeedbackManager.shared.speak("Crosswalk")
        case let route as RouteFeature:
            FeedbackManager.shared.startRoutePulsing()
            FeedbackManager.shared.speak(route.explorationAnnouncement)
        case let sidewalk as SidewalkFeature:
            FeedbackManager.shared.startContinuousSound()
            FeedbackManager.shared.speak(sidewalk.announcement)
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
        let threshold = max(half, 22)
        for feature in currentIntersections {
            let center = mapView.convert(feature.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= threshold {
                return feature
            }
        }
        return nil
    }

    private func crosswalk(at point: CGPoint, in mapView: MKMapView) -> CrosswalkFeature? {
        let threshold = PhysicalDimensions.mmToPoints(MapCrosswalkStyle.lineWidthMM)
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
}
