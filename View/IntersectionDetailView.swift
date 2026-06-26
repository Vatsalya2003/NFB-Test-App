// IntersectionDetailView.swift
// Level 2 — zoomed-in intersection view. Loads intersection-specific JSON,
// shows wider roads (12 mm), sidewalks (4 mm), crosswalks, and route overlay.
// Double-tap the route end dot (or anywhere) or three-finger swipe goes back to Level 1.

import SwiftUI
import MapKit

struct IntersectionDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var detailFeatures: [MapFeature] = []
    @State private var detailRoutes: [RouteFeature] = []
    @State private var detailRouteTurns: [RouteTurnFeature] = []
    @State private var hasAnnouncedScreenIntro = false

    let intersection: IntersectionFeature
    let intersectionName: String
    let routeFile: String
    let routeTitle: String

    init(intersection: IntersectionFeature, routeFile: String, routeTitle: String = "") {
        self.intersection = intersection
        self.intersectionName = intersection.properties["name"] as? String ?? "Intersection"
        self.routeFile = routeFile
        self.routeTitle = routeTitle.isEmpty ? Self.defaultRouteTitle(for: routeFile) : routeTitle
    }

    var body: some View {
        IntersectionDetailMapView(
            features: detailFeatures,
            routes: detailRoutes,
            routeTurns: detailRouteTurns,
            intersectionName: intersectionName,
            rotateMap180: false,
            onBackGesture: {
                goBack()
            }
        )
        .ignoresSafeArea(.container)
        .navigationBarTitle("Intersection View", displayMode: .inline)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            loadIntersectionData()
            DataService.shared.setIntersectionCondition(
                routeTitle: routeTitle,
                intersectionName: intersectionName
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            announceScreenIntroIfNeeded()
        }
        .onDisappear {
            DataService.shared.setMapOverviewCondition(routeTitle: routeTitle)
            FeedbackManager.shared.stopAllFeedback()
            AccessibleMapView.suppressVoiceOverLayoutFocus = true
        }
        .accessibilityAction(.escape) {
            goBack()
        }
        .disableInteractivePopGesture()
    }

    private func loadIntersectionData() {
        FeedbackManager.shared.presentationMode = .naturalLanguage

        let filename = "intersection_\(intersection.id)_detail"
        let mirror = MapOrientation.shouldMirrorMap(forRouteFile: routeFile)
        detailFeatures = MapDataLoader.loadMapFeatures(
            from: filename,
            mirror180: mirror,
            routeFile: routeFile,
            includeLandmarks: false,
            stretchFactor: MapDataLoader.intersectionDetailStretchFactor
        )

        detailRoutes = IntersectionRouteLoader.loadRoutes(from: filename, routeFile: routeFile, mirror180: mirror)
        detailRouteTurns = detailRoutes.flatMap { RouteTurnFeature.turns(for: $0) }

        if UIAccessibility.isVoiceOverRunning, !hasAnnouncedScreenIntro {
            announceScreenIntroIfNeeded()
        }
    }

    private func announceScreenIntroIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning, !hasAnnouncedScreenIntro else { return }
        hasAnnouncedScreenIntro = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let message = "Intersection view"
            UIAccessibility.post(notification: .screenChanged, argument: message)
        }
    }

    private func goBack() {
        FeedbackManager.shared.stopAllFeedback()
        AccessibleMapView.suppressVoiceOverLayoutFocus = true
        presentationMode.wrappedValue.dismiss()
    }

    private static func defaultRouteTitle(for routeFile: String) -> String {
        switch routeFile {
        case "route_jwmarriott_to_marriott":
            return "JW Marriott → Austin Marriott"
        case "route_marriott_to_jwmarriott":
            return "Marriott → JW Marriott"
        default:
            return routeFile.replacingOccurrences(of: "route_", with: "").replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Route loader for intersection detail JSONs

class IntersectionRouteLoader {
    static func loadRoutes(from filename: String, routeFile: String, mirror180: Bool = false) -> [RouteFeature] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routeJSON = json["route"] as? [String: Any],
              let geometry = routeJSON["geometry"] as? [String: Any],
              let coordinates = geometry["coordinates"] as? [[Double]],
              var properties = routeJSON["properties"] as? [String: Any] else {
            return []
        }

        let mirroredCoords = mirror180
            ? coordinates.map { MapOrientation.mirrorDesignerCoordinate($0) }
            : coordinates

        let stretch = MapDataLoader.intersectionDetailStretchFactor

        var processedCoords = mirroredCoords.map { coord -> [Double] in
            let layoutCoord = MapIntersectionLayout.remapCoordinate(coord, yStretchFactor: stretch)
            guard layoutCoord.count >= 2 else { return layoutCoord }
            let centerY = 500.0
            let x = layoutCoord[0]
            let y = layoutCoord[1]
            let stretchedY = centerY + (y - centerY) * stretch
            return [x, stretchedY]
        }

        if MapOrientation.shouldReverseIntersectionRoute(forRouteFile: routeFile) {
            processedCoords.reverse()
            let departure = properties["departure"] as? String
            let destination = properties["destination"] as? String
            properties["departure"] = destination ?? "Route"
            properties["destination"] = departure ?? "Route"
        }

        processedCoords = clampRouteEndpointsToStreetLegs(processedCoords)

        let route = RouteFeature(
            id: "intersection_route",
            coordinates: processedCoords,
            properties: properties
        )
        return [route]
    }

    /// Keeps route start/end on the blue street leg tips (designer 100 / 900), never past the screen.
    private static func clampRouteEndpointsToStreetLegs(_ coords: [[Double]]) -> [[Double]] {
        guard coords.count >= 2 else { return coords }
        var result = coords
        let low = MapIntersectionLayout.legInnerBound
        let high = MapIntersectionLayout.legOuterBound

        result[0] = clampEndpoint(result[0], toward: result[1], low: low, high: high)
        let last = result.count - 1
        result[last] = clampEndpoint(result[last], toward: result[last - 1], low: low, high: high)
        return result
    }

    private static func clampEndpoint(
        _ point: [Double],
        toward anchor: [Double],
        low: Double,
        high: Double
    ) -> [Double] {
        guard point.count >= 2, anchor.count >= 2 else { return point }
        var x = point[0]
        var y = point[1]

        if abs(point[0] - anchor[0]) >= abs(point[1] - anchor[1]) {
            x = min(max(x, low), high)
        } else {
            y = min(max(y, low), high)
        }
        return [x, y]
    }
}
