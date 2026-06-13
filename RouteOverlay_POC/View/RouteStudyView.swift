// RouteStudyView.swift
// Loads the base map + one route file, then shows RouteMapView full screen.
// Double-tapping an intersection navigates to Level 2 (intersection detail view).

import SwiftUI
import MapKit

struct RouteStudyView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mapFeatures: [MapFeature] = []
    @State private var routes: [RouteFeature] = []
    @State private var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    @State private var selectedIntersection: IntersectionFeature?

    let routeFile: String
    let baseMapFile: String
    let title: String

    init(title: String = "Marriott → JW Marriott",
         routeFile: String = "route_marriott_to_jwmarriott") {
        self.title = title
        self.baseMapFile = "testMap_Condition1"
        self.routeFile = routeFile
    }

    var body: some View {
        RouteMapView(
            features: mapFeatures,
            routes: routes,
            isInteractionEnabled: true,
            onThreeFingerSwipe: {
                performBackNavigation()
            },
            onIntersectionDoubleTap: { intersection in
                selectedIntersection = intersection
            }
        )
        .ignoresSafeArea(.container)
        .navigationBarTitle(title, displayMode: .inline)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            setupView()
        }
        .onDisappear {
            FeedbackManager.shared.stopAllFeedback()
        }
        .accessibilityAction(named: "Escape") {
            performBackNavigation()
        }
        .background(
            NavigationLink(
                destination: selectedIntersection.map { IntersectionDetailView(intersection: $0) },
                isActive: Binding(
                    get: { selectedIntersection != nil },
                    set: { if !$0 { selectedIntersection = nil } }
                ),
                label: { EmptyView() }
            )
        )
    }

    private func setupView() {
        FeedbackManager.shared.presentationMode = .naturalLanguage

        mapFeatures = MapDataLoader.loadMapFeatures(from: baseMapFile)
        routes = RouteMapDataLoader.loadRouteFeatures(from: routeFile)

        print("Loaded \(mapFeatures.count) map features and \(routes.count) route(s)")

        if UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let message = "Navigation map. Blue lines show streets. Touch roads for vibration feedback. Double tap an intersection to zoom in."
                UIAccessibility.post(notification: .screenChanged, argument: message)
            }
        }
    }

    private func performBackNavigation() {
        FeedbackManager.shared.stopAllFeedback()
        presentationMode.wrappedValue.dismiss()
    }
}

#Preview {
    NavigationView {
        RouteStudyView()
    }
}
