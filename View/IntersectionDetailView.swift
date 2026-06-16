// IntersectionDetailView.swift
// Level 2 — zoomed-in intersection view. Loads intersection-specific JSON,
// shows wider roads (8mm), sidewalks, crosswalks, route overlay, and POIs.
// Double-tap the route end dot (or anywhere) or three-finger swipe goes back to Level 1.

import SwiftUI
import MapKit

struct IntersectionDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var detailFeatures: [MapFeature] = []
    @State private var detailRoutes: [RouteFeature] = []

    let intersection: IntersectionFeature
    let intersectionName: String

    init(intersection: IntersectionFeature) {
        self.intersection = intersection
        self.intersectionName = intersection.properties["name"] as? String ?? "Intersection"
    }

    var body: some View {
        IntersectionDetailMapView(
            features: detailFeatures,
            routes: detailRoutes,
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
        detailFeatures = MapDataLoader.loadMapFeatures(from: filename)

        // Load route segment if present in the intersection detail JSON
        detailRoutes = IntersectionRouteLoader.loadRoutes(from: filename)

        if UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let message = "Zoomed in to \(intersectionName). Follow the route to the yellow end dot. Double tap the end dot to return to route overview."
                UIAccessibility.post(notification: .screenChanged, argument: message)
            }
        }
    }

    private func goBack() {
        FeedbackManager.shared.stopAllFeedback()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: "Back to route overview")
        }

        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Route loader for intersection detail JSONs

class IntersectionRouteLoader {
    static func loadRoutes(from filename: String) -> [RouteFeature] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routeJSON = json["route"] as? [String: Any],
              let geometry = routeJSON["geometry"] as? [String: Any],
              let coordinates = geometry["coordinates"] as? [[Double]],
              let properties = routeJSON["properties"] as? [String: Any] else {
            return []
        }

        let stretchedCoords = coordinates.map { coord -> [Double] in
            let layoutCoord = MapIntersectionLayout.remapCoordinate(coord)
            guard layoutCoord.count >= 2 else { return layoutCoord }
            let centerY = 500.0
            let x = layoutCoord[0]
            let y = layoutCoord[1]
            let stretchedY = centerY + (y - centerY) * MapDataLoader.stretchFactor
            return [x, stretchedY]
        }

        let route = RouteFeature(
            id: "intersection_route",
            coordinates: stretchedCoords,
            properties: properties
        )
        return [route]
    }
}
