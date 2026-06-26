// FeedbackCustomizationTesterView.swift
// Dev tool on home screen — preview map and try different haptic patterns per element.
// Default patterns match HapticService (street heavy buzz, route pulse, etc.).

import SwiftUI
import MapKit
import CoreHaptics
import AudioToolbox

// MARK: - Custom Haptic Engine

/// Plays user-selected Core Haptics patterns for both short previews
/// (pattern buttons) and looping continuous playback (map exploration).
class CustomHapticEngine: ObservableObject {
    private var previewPlayer: CHHapticPatternPlayer?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var activePattern: HapticPatternType?
    private var dingTimer: Timer?

    @Published var touchedElementLabel: String?

    // MARK: Preview (short, auto-stops after ~1.5s)

    func preview(_ pattern: HapticPatternType) {
        stopAll()
        guard let engine = HapticService.shared.hapticEngine else { return }
        do {
            try engine.start()
            let p = try Self.buildPreviewPattern(for: pattern)
            previewPlayer = try engine.makePlayer(with: p)
            try previewPlayer?.start(atTime: CHHapticTimeImmediate)
            if pattern == .intersectionSlowPulse {
                AudioServicesPlaySystemSound(1057)
            }
        } catch {
            print("Haptic preview failed: \(error)")
        }
    }

    // MARK: Continuous (loops until stopped)

    func startContinuous(_ pattern: HapticPatternType) {
        if activePattern == pattern { return }
        stopContinuous()
        guard let engine = HapticService.shared.hapticEngine else { return }
        do {
            try engine.start()
            let p = try Self.buildContinuousPattern(for: pattern)
            continuousPlayer = try engine.makeAdvancedPlayer(with: p)
            continuousPlayer?.loopEnabled = true
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            activePattern = pattern

            if pattern == .intersectionSlowPulse {
                AudioServicesPlaySystemSound(1057)
                dingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                    guard self?.activePattern == .intersectionSlowPulse else { return }
                    AudioServicesPlaySystemSound(1057)
                }
            }
        } catch {
            print("Continuous haptic failed: \(error)")
        }
    }

    func stopContinuous() {
        dingTimer?.invalidate()
        dingTimer = nil
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Stop haptic failed: \(error)")
        }
        continuousPlayer = nil
        activePattern = nil
    }

    func stopAll() {
        try? previewPlayer?.stop(atTime: CHHapticTimeImmediate)
        previewPlayer = nil
        stopContinuous()
    }

    // MARK: Pattern Builders (production defaults mirror HapticService)

    static func buildPreviewPattern(for type: HapticPatternType) throws -> CHHapticPattern {
        try buildPattern(for: type, loopCount: previewLoopCount(for: type), durationScale: 1.0)
    }

    static func buildContinuousPattern(for type: HapticPatternType) throws -> CHHapticPattern {
        try buildPattern(for: type, loopCount: continuousLoopCount(for: type), durationScale: 1.0)
    }

    private static func previewLoopCount(for type: HapticPatternType) -> Int {
        switch type {
        case .streetContinuous, .lightContinuous, .heavyBuzz: return 1
        case .routeRhythmic: return 8
        case .intersectionSlowPulse: return 6
        case .landmarkFastPulse: return 10
        case .sharpTransient: return 3
        }
    }

    private static func continuousLoopCount(for type: HapticPatternType) -> Int {
        switch type {
        case .streetContinuous, .lightContinuous, .heavyBuzz: return 1
        case .routeRhythmic: return 50
        case .intersectionSlowPulse: return 20
        case .landmarkFastPulse: return 80
        case .sharpTransient: return 6
        }
    }

    private static func buildPattern(
        for type: HapticPatternType,
        loopCount: Int,
        durationScale: Double
    ) throws -> CHHapticPattern {
        switch type {
        case .streetContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.78),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.78)
                ], relativeTime: 0, duration: loopCount == 1 ? 1.5 * durationScale : 100.0)
            ], parameters: [])

        case .routeRhythmic:
            // Route: 0.12s on / 0.08s off at 100% (HapticService+Route)
            let interval = 0.2 * durationScale
            let duration = 0.12 * durationScale
            let events = (0..<loopCount).map { i in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                ], relativeTime: TimeInterval(i) * interval, duration: duration)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .intersectionSlowPulse:
            // Intersection: 0.15s on / 0.35s off at 100% (HapticService pulseInterval)
            let interval = 0.25 * durationScale
            let duration = 0.15 * durationScale
            let events = (0..<loopCount).map { i in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: TimeInterval(i) * interval, duration: duration)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .landmarkFastPulse:
            // Landmark: 0.08s on / 0.04s off at 100% (HapticService landmark timing)
            let interval = 0.12 * durationScale
            let duration = 0.08 * durationScale
            let events = (0..<loopCount).map { i in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ], relativeTime: TimeInterval(i) * interval, duration: duration)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .lightContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0, duration: 3.0 * durationScale)
            ], parameters: [])

        case .sharpTransient:
            let events = (0..<loopCount).map { i in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: TimeInterval(i) * 0.15)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .heavyBuzz:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ], relativeTime: 0, duration: loopCount == 1 ? 1.5 * durationScale : 100.0)
            ], parameters: [])
        }
    }
}

// MARK: - Tester Static Map View

struct TesterStaticMapView: UIViewRepresentable {
    let features: [MapFeature]
    let routes: [RouteFeature]
    var selections: [MapElementType: HapticPatternType]
    let engine: CustomHapticEngine

    private func applyVisibleRect(to mapView: MKMapView) {
        let padding: UIEdgeInsets
        if let fitting = mapView as? FittingMapView {
            padding = fitting.fitToSafeArea ? fitting.safeAreaInsets : fitting.customEdgePadding
        } else {
            padding = .zero
        }
        MapVisibleRectHelper.fitMapView(
            mapView,
            features: features,
            routes: routes,
            edgePadding: padding
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = FittingMapView()
        mapView.fitFeatures = features
        mapView.fitRoutes = routes
        mapView.fitToSafeArea = false
        mapView.customEdgePadding = UIEdgeInsets(top: 30, left: 40, bottom: 155, right: 40)

        mapView.mapType = .mutedStandard
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

        applyVisibleRect(to: mapView)
        DispatchQueue.main.async {
            self.applyVisibleRect(to: mapView)
        }

        mapView.delegate = context.coordinator

        let blankOverlay = BlankTileOverlay()
        mapView.addOverlay(blankOverlay, level: .aboveLabels)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(TesterMapCoordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.1
        longPress.allowableMovement = 10000

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(TesterMapCoordinator.handleSingleTap(_:))
        )
        singleTap.require(toFail: longPress)

        mapView.addGestureRecognizer(longPress)
        mapView.addGestureRecognizer(singleTap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.features = features
        context.coordinator.routes = routes
        context.coordinator.selections = selections

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        features.filter { $0.featureType == "corridor" }.forEach { $0.addToMap(mapView) }
        features.compactMap { $0 as? IntersectionFeature }.forEach { $0.addToMap(mapView) }
        features.compactMap { $0 as? LandmarkFeature }.forEach { $0.addToMap(mapView) }
        routes.forEach { $0.addToMap(mapView) }

        if let fittingMapView = mapView as? FittingMapView {
            fittingMapView.fitFeatures = features
            fittingMapView.fitRoutes = routes
        }
        applyVisibleRect(to: mapView)
    }

    func makeCoordinator() -> TesterMapCoordinator {
        TesterMapCoordinator(engine: engine)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: TesterMapCoordinator) {
        coordinator.engine.stopAll()
    }
}

// MARK: - Tester Map Coordinator

class TesterMapCoordinator: NSObject, MKMapViewDelegate {
    var features: [MapFeature] = []
    var routes: [RouteFeature] = []
    var selections: [MapElementType: HapticPatternType] = [:]
    let engine: CustomHapticEngine

    private var activeFeature: MapFeature?
    private var lastUpdateTime: TimeInterval = 0
    private let updateThreshold: TimeInterval = 0.1

    init(engine: CustomHapticEngine) {
        self.engine = engine
        super.init()
    }

    // MARK: Gesture Handlers

    @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)
        let feature = findFeature(at: point, in: mapView)

        if let feature = feature,
           let elementType = MapElementType.from(featureType: feature.featureType),
           let pattern = selections[elementType] {
            engine.preview(pattern)
            DispatchQueue.main.async {
                self.engine.touchedElementLabel = elementType.rawValue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                if self.activeFeature == nil {
                    self.engine.touchedElementLabel = nil
                }
            }
        }
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)
        let currentTime = CACurrentMediaTime()

        switch gesture.state {
        case .began:
            startFeedback(at: point, in: mapView)
        case .changed:
            if currentTime - lastUpdateTime > updateThreshold {
                lastUpdateTime = currentTime
                updateFeedback(at: point, in: mapView)
            }
        case .ended, .cancelled, .failed:
            stopFeedback()
        default:
            break
        }
    }

    // MARK: Feedback Dispatch

    private func startFeedback(at point: CGPoint, in mapView: MKMapView) {
        engine.stopContinuous()
        let feature = findFeature(at: point, in: mapView)
        activeFeature = feature

        if let feature = feature,
           let elementType = MapElementType.from(featureType: feature.featureType),
           let pattern = selections[elementType] {
            engine.startContinuous(pattern)
            DispatchQueue.main.async { self.engine.touchedElementLabel = elementType.rawValue }
        } else {
            DispatchQueue.main.async { self.engine.touchedElementLabel = nil }
        }
    }

    private func updateFeedback(at point: CGPoint, in mapView: MKMapView) {
        let newFeature = findFeature(at: point, in: mapView)

        if newFeature?.id != activeFeature?.id {
            engine.stopContinuous()
            activeFeature = newFeature

            if let feature = newFeature,
               let elementType = MapElementType.from(featureType: feature.featureType),
               let pattern = selections[elementType] {
                engine.startContinuous(pattern)
                DispatchQueue.main.async { self.engine.touchedElementLabel = elementType.rawValue }
            } else {
                DispatchQueue.main.async { self.engine.touchedElementLabel = nil }
            }
        }
    }

    private func stopFeedback() {
        engine.stopContinuous()
        activeFeature = nil
        DispatchQueue.main.async { self.engine.touchedElementLabel = nil }
    }

    // MARK: Hit Testing

    private func findFeature(at point: CGPoint, in mapView: MKMapView) -> MapFeature? {
        for feature in features.compactMap({ $0 as? IntersectionFeature }) {
            if isPointNearFeature(point, feature: feature, in: mapView) { return feature }
        }
        for feature in features.compactMap({ $0 as? LandmarkFeature }) {
            if isPointNearFeature(point, feature: feature, in: mapView) { return feature }
        }
        if let route = route(at: point, in: mapView) { return route }
        for feature in features where feature.featureType == "corridor" {
            if isPointNearFeature(point, feature: feature, in: mapView) { return feature }
        }
        return nil
    }

    private func route(at point: CGPoint, in mapView: MKMapView) -> RouteFeature? {
        let threshold = max(PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM) / 2, 22)
        for route in routes {
            for i in 0..<(route.coordinates.count - 1) {
                let a = mapView.convert(route.coordinates[i], toPointTo: mapView)
                let b = mapView.convert(route.coordinates[i + 1], toPointTo: mapView)
                if distanceFromPoint(point, toLineFrom: a, to: b) < threshold {
                    return route
                }
            }
        }
        return nil
    }

    private func isPointNearFeature(_ point: CGPoint, feature: MapFeature, in mapView: MKMapView) -> Bool {
        switch feature.featureType {
        case "landmark":
            if let landmark = feature as? LandmarkFeature {
                let anchor = mapView.convert(landmark.coordinate, toPointTo: mapView)
                let offset = MapLandmarkStyle.sideOffset(landmark.side)
                let box = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
                let boxThreshold = max(PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxWidthMM) / 2, 22)
                if hypot(point.x - anchor.x, point.y - anchor.y) < 30
                    || hypot(point.x - box.x, point.y - box.y) < boxThreshold {
                    return true
                }
            }
        case "intersection":
            if let intersection = feature as? IntersectionFeature {
                let fp = mapView.convert(intersection.coordinate, toPointTo: mapView)
                let half = max(PhysicalDimensions.mmToPoints(MapIntersectionStyle.sideMM) / 2, 22)
                return hypot(point.x - fp.x, point.y - fp.y) < half
            }
        case "corridor":
            if let corridor = feature as? CorridorFeature {
                let threshold = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM) / 2
                for i in 0..<(corridor.coordinates.count - 1) {
                    let a = mapView.convert(corridor.coordinates[i], toPointTo: mapView)
                    let b = mapView.convert(corridor.coordinates[i + 1], toPointTo: mapView)
                    if distanceFromPoint(point, toLineFrom: a, to: b) < threshold {
                        return true
                    }
                }
            }
        default:
            break
        }
        return false
    }

    private func distanceFromPoint(_ p: CGPoint, toLineFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let len = hypot(b.x - a.x, b.y - a.y)
        if len == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (len * len)))
        return hypot(p.x - (a.x + t * (b.x - a.x)), p.y - (a.y + t * (b.y - a.y)))
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
            let reuseID = "tester_intersection"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? IntersectionAnnotationView
                ?? IntersectionAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }
        if annotation is LandmarkFeature {
            let reuseID = "tester_landmark"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? LandmarkAnnotationView
                ?? LandmarkAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }
        return nil
    }
}

// MARK: - Screen 1: Feedback Customization Tester View (Pattern Picker)

struct FeedbackCustomizationTesterView: View {
    @State private var selections: [MapElementType: HapticPatternType] = HapticFeedbackSelection.defaults.selections
    @StateObject private var engine = CustomHapticEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                ForEach(MapElementType.allCases) { element in
                    elementSection(for: element)
                }

                startMapButton
            }
            .padding(.vertical)
        }
        .navigationTitle("Feedback Setup")
        .navigationBarTitleDisplayMode(.inline)
        .disableInteractivePopGesture()
        .onAppear { FeedbackManager.shared.stopAllFeedback() }
        .onDisappear { engine.stopAll() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 40))
                .foregroundColor(.purple)

            Text("Customize Haptic Feedback")
                .font(.title2)
                .fontWeight(.bold)

            Text("Defaults match the live route study map. Tap a pattern to preview, assign per element, then explore.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    // MARK: Element Section

    private func elementSection(for element: MapElementType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage(for: element))
                    .font(.title3)
                    .foregroundColor(accentColor(for: element))
                    .frame(width: 28)
                Text(element.rawValue)
                    .font(.headline)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(HapticPatternType.allCases) { pattern in
                        patternButton(pattern, for: element)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Pattern Button

    private func patternButton(_ pattern: HapticPatternType, for element: MapElementType) -> some View {
        let isSelected = selections[element] == pattern
        let color = accentColor(for: element)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selections[element] = pattern
            }
            engine.preview(pattern)
        } label: {
            VStack(spacing: 6) {
                Text(pattern.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                Text(pattern.shortName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? color : .secondary)
            }
            .frame(width: 74, height: 58)
            .background(isSelected ? color.opacity(0.15) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pattern.label): \(pattern.shortName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Start Map Button

    private var startMapButton: some View {
        NavigationLink(destination: TesterMapExplorationView(
            selections: selections
        )) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                Text("Start Map")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 30)
    }

    // MARK: Helpers

    private func systemImage(for element: MapElementType) -> String {
        switch element {
        case .corridor: return "line.3.horizontal"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .intersection: return "arrow.triangle.branch"
        case .landmark: return "mappin.and.ellipse"
        }
    }

    private func accentColor(for element: MapElementType) -> Color {
        switch element {
        case .corridor: return .blue
        case .route: return .cyan
        case .intersection: return .red
        case .landmark: return .purple
        }
    }
}

// MARK: - Screen 2: Tester Map Exploration View (Full-Screen Map)

struct TesterMapExplorationView: View {
    let selections: [MapElementType: HapticPatternType]

    @State private var features: [MapFeature] = []
    @State private var routes: [RouteFeature] = []
    @StateObject private var engine = CustomHapticEngine()

    var body: some View {
        ZStack(alignment: .bottom) {
            TesterStaticMapView(
                features: features,
                routes: routes,
                selections: selections,
                engine: engine
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if let label = engine.touchedElementLabel {
                Text("Touching: \(label)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("Explore Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .disableInteractivePopGesture()
        .onAppear {
            FeedbackManager.shared.stopAllFeedback()
            features = MapDataLoader.loadMapFeatures(from: "testMap_Condition1")
            routes = RouteMapDataLoader.loadRouteFeatures(from: "route_marriott_to_jwmarriott")
        }
        .onDisappear {
            engine.stopAll()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FeedbackCustomizationTesterView()
    }
}
