// IntersectionDetailView.swift
// Level 2 — zoomed-in intersection view. Loads intersection-specific JSON,
// shows wider roads (12 mm), sidewalks (4 mm), crosswalks, route overlay, and POIs.
// Double-tap the route end dot (or anywhere) or three-finger swipe goes back to Level 1.

import SwiftUI
import MapKit

struct IntersectionDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var detailFeatures: [MapFeature] = []
    @State private var detailRoutes: [RouteFeature] = []

    let intersection: IntersectionFeature
    let intersectionName: String
    let routeFile: String

    init(intersection: IntersectionFeature, routeFile: String) {
        self.intersection = intersection
        self.intersectionName = intersection.properties["name"] as? String ?? "Intersection"
        self.routeFile = routeFile
    }

    var body: some View {
        IntersectionDetailMapView(
            features: detailFeatures,
            routes: detailRoutes,
            intersectionName: intersectionName,
            rotateMap180: false,
            onBackGesture: {
                goBack()
            }
        )
        .ignoresSafeArea(.container)
        .navigationBarTitle("Intersection Detail", displayMode: .inline)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            loadIntersectionData()
        }
        .onDisappear {
            FeedbackManager.shared.stopAllFeedback()
        }
        .accessibilityAction(named: "Escape") {
            goBack()
        }
        .disableInteractivePopGesture()
    }

    private func loadIntersectionData() {
        FeedbackManager.shared.presentationMode = .naturalLanguage

        let filename = "intersection_\(intersection.id)_detail"
        let mirror = MapOrientation.shouldMirrorMap(forRouteFile: routeFile)
        detailFeatures = MapDataLoader.loadMapFeatures(from: filename, mirror180: mirror)

        detailRoutes = IntersectionRouteLoader.loadRoutes(from: filename, routeFile: routeFile, mirror180: mirror)

        if UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let message = "Zoomed in to \(intersectionName). Follow the route to the yellow end dot. You will hear end of route. Double tap the end dot to return to map overview."
                UIAccessibility.post(notification: .screenChanged, argument: message)
            }
        }
    }

    private func goBack() {
        FeedbackManager.shared.stopAllFeedback()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: "Back to map overview")
        }

        presentationMode.wrappedValue.dismiss()
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

        var stretchedCoords = mirroredCoords.map { coord -> [Double] in
            let layoutCoord = MapIntersectionLayout.remapCoordinate(coord)
            guard layoutCoord.count >= 2 else { return layoutCoord }
            let centerY = 500.0
            let x = layoutCoord[0]
            let y = layoutCoord[1]
            let stretchedY = centerY + (y - centerY) * MapDataLoader.stretchFactor
            return [x, stretchedY]
        }

        if MapOrientation.shouldReverseIntersectionRoute(forRouteFile: routeFile) {
            stretchedCoords.reverse()
            let departure = properties["departure"] as? String
            let destination = properties["destination"] as? String
            properties["departure"] = destination ?? "Route"
            properties["destination"] = departure ?? "Route"
        }

        let route = RouteFeature(
            id: "intersection_route",
            coordinates: stretchedCoords,
            properties: properties
        )
        return [route]
    }
}
