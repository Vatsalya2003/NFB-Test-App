import SwiftUI
import MapKit
import CoreHaptics

// MARK: - Custom Haptic Engine

/// Plays user-selected Core Haptics patterns for both short previews
/// (pattern buttons) and looping continuous playback (map exploration).
class CustomHapticEngine: ObservableObject {
    private var previewPlayer: CHHapticPatternPlayer?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var activePattern: HapticPatternType?

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
        } catch {
            print("Continuous haptic failed: \(error)")
        }
    }

    func stopContinuous() {
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

    // MARK: Pattern Builders

    static func buildPreviewPattern(for type: HapticPatternType) throws -> CHHapticPattern {
        switch type {
        case .lightContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0, duration: 1.5)
            ], parameters: [])

        case .mediumContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0, duration: 1.5)
            ], parameters: [])

        case .sharpTransient:
            let events = (0..<3).map { i in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: TimeInterval(i) * 0.15)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .rhythmicPulse:
            let events = (0..<8).map { i in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: TimeInterval(i) * 0.2, duration: 0.1)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .heavyBuzz:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ], relativeTime: 0, duration: 1.5)
            ], parameters: [])
        }
    }

    static func buildContinuousPattern(for type: HapticPatternType) throws -> CHHapticPattern {
        switch type {
        case .lightContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0, duration: 3.0)
            ], parameters: [])

        case .mediumContinuous:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0, duration: 3.0)
            ], parameters: [])

        case .sharpTransient:
            let events = (0..<6).map { i in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: TimeInterval(i) * 0.15)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .rhythmicPulse:
            let events = (0..<10).map { i in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: TimeInterval(i) * 0.2, duration: 0.1)
            }
            return try CHHapticPattern(events: events, parameters: [])

        case .heavyBuzz:
            return try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ], relativeTime: 0, duration: 3.0)
            ], parameters: [])
        }
    }
}

// MARK: - Tester Static Map View

struct TesterStaticMapView: UIViewRepresentable {
    let features: [MapFeature]
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
            features: MapVisibleRectHelper.corridorFeatures(from: features),
            edgePadding: padding
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = FittingMapView()
        mapView.fitFeatures = MapVisibleRectHelper.corridorFeatures(from: features)
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
        let corridorFeatures = MapVisibleRectHelper.corridorFeatures(from: features)
        context.coordinator.features = corridorFeatures
        context.coordinator.selections = selections

        let featureOverlays = mapView.overlays.filter { !($0 is BlankTileOverlay) }
        mapView.removeOverlays(featureOverlays)
        mapView.removeAnnotations(mapView.annotations)

        corridorFeatures.forEach { $0.addToMap(mapView) }

        if let fittingMapView = mapView as? FittingMapView {
            fittingMapView.fitFeatures = corridorFeatures
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
           let elementType = mapElementType(for: feature.featureType),
           let pattern = selections[elementType] {
            engine.preview(pattern)
            DispatchQueue.main.async {
                self.engine.touchedElementLabel = feature.featureType.capitalized
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
           let elementType = mapElementType(for: feature.featureType),
           let pattern = selections[elementType] {
            engine.startContinuous(pattern)
            DispatchQueue.main.async { self.engine.touchedElementLabel = feature.featureType.capitalized }
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
               let elementType = mapElementType(for: feature.featureType),
               let pattern = selections[elementType] {
                engine.startContinuous(pattern)
                DispatchQueue.main.async { self.engine.touchedElementLabel = feature.featureType.capitalized }
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
        for feature in features where feature.featureType == "intersection" || feature.featureType == "landmark" {
            if isPointNearFeature(point, feature: feature, in: mapView) {
                return feature
            }
        }
        // Purple anchor dots on corridors should trigger landmark feedback
        for annotation in mapView.annotations {
            if let anchor = annotation as? LandmarkAnchorAnnotation {
                let anchorPoint = mapView.convert(anchor.coordinate, toPointTo: mapView)
                let diameter = PhysicalDimensions.mmToPoints(8.0)
                if hypot(point.x - anchorPoint.x, point.y - anchorPoint.y) < diameter / 2 {
                    return anchor.landmark
                }
            }
        }
        for feature in features where feature.featureType == "corridor" {
            if isPointNearFeature(point, feature: feature, in: mapView) {
                return feature
            }
        }
        return nil
    }

    private func isPointNearFeature(_ point: CGPoint, feature: MapFeature, in mapView: MKMapView) -> Bool {
        switch feature.featureType {
        case "landmark":
            if let landmark = feature as? LandmarkFeature {
                let fp = mapView.convert(landmark.coordinate, toPointTo: mapView)
                return hypot(point.x - fp.x, point.y - fp.y) < 25
            }
        case "intersection":
            if let intersection = feature as? IntersectionFeature {
                let fp = mapView.convert(intersection.coordinate, toPointTo: mapView)
                return hypot(point.x - fp.x, point.y - fp.y) < 25
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

    private func mapElementType(for featureType: String) -> MapElementType? {
        switch featureType {
        case "corridor": return .corridor
        case "intersection": return .intersection
        case "landmark": return .landmark
        default: return nil
        }
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is BlankTileOverlay {
            return WhiteTileRenderer(overlay: overlay)
        }
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = MapRoadStyle.blue
            renderer.lineWidth = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM)
            renderer.lineCap = .square
            renderer.lineJoin = .miter
            renderer.miterLimit = 10
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let anchor = annotation as? LandmarkAnchorAnnotation {
            let view = MKAnnotationView(annotation: anchor, reuseIdentifier: "tester_anchor")
            let diameter = PhysicalDimensions.mmToPoints(8.0)
            view.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            view.backgroundColor = .systemPurple
            view.layer.cornerRadius = diameter / 2
            view.layer.borderWidth = PhysicalDimensions.mmToPoints(0.5)
            view.layer.borderColor = UIColor.white.cgColor
            view.displayPriority = .defaultLow
            if #available(iOS 14.0, *) {
                view.zPriority = .min
            }
            return view
        }
        if let intersection = annotation as? IntersectionFeature {
            return IntersectionAnnotationView(annotation: intersection, reuseIdentifier: "tester_intersection")
        }
        if let landmark = annotation as? LandmarkFeature {
            let view = MKAnnotationView(annotation: landmark, reuseIdentifier: "tester_landmark")
            let w = PhysicalDimensions.mmToPoints(6.0)
            let h = PhysicalDimensions.mmToPoints(4.0)
            view.frame = CGRect(x: 0, y: 0, width: w, height: h)
            view.backgroundColor = .systemRed
            view.layer.borderWidth = PhysicalDimensions.mmToPoints(0.75)
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.cornerRadius = PhysicalDimensions.mmToPoints(1.0)
            let label = UILabel(frame: view.bounds)
            label.text = landmark.title?.first?.uppercased() ?? "L"
            label.textAlignment = .center
            label.textColor = .white
            label.font = .boldSystemFont(ofSize: PhysicalDimensions.mmToPoints(3.0))
            label.adjustsFontSizeToFitWidth = true
            view.addSubview(label)
            view.canShowCallout = false
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

            Text("Tap a pattern to feel it, then choose one for each element.")
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
        case .intersection: return "arrow.triangle.branch"
        case .landmark: return "mappin.and.ellipse"
        }
    }

    private func accentColor(for element: MapElementType) -> Color {
        switch element {
        case .corridor: return .blue
        case .intersection: return .red
        case .landmark: return .red
        }
    }
}

// MARK: - Screen 2: Tester Map Exploration View (Full-Screen Map)

struct TesterMapExplorationView: View {
    let selections: [MapElementType: HapticPatternType]

    @State private var features: [MapFeature] = []
    @StateObject private var engine = CustomHapticEngine()

    var body: some View {
        ZStack(alignment: .bottom) {
            TesterStaticMapView(
                features: features,
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
        .onAppear {
            features = MapDataLoader.loadMapFeatures(from: "testMap_Condition1")
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
