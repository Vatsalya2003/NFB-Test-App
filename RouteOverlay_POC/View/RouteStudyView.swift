// RouteStudyView.swift
// Loads the base map + one route file, then shows RouteMapView full screen.
// Double-tapping an intersection navigates to Level 2 (intersection detail view).

import SwiftUI
import MapKit

private struct IntersectionZoomSelection: Identifiable, Hashable {
    let id: String
}

struct RouteStudyView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mapFeatures: [MapFeature] = []
    @State private var routes: [RouteFeature] = []
    @State private var hasAnnouncedScreenIntro = false
    @State private var hasAnnouncedMapOverviewThisVisit = false
    @State private var intersectionZoomSelection: IntersectionZoomSelection?
    /// Keeps the CSV session alive while intersection detail is on the navigation stack.
    @State private var holdSessionForIntersection = false

    let routeFile: String
    let baseMapFile: String
    let title: String

    init(title: String = "Marriott → JW Marriott",
         routeFile: String = "route_marriott_to_jwmarriott") {
        self.title = title
        self.baseMapFile = "testMap_Condition1"
        self.routeFile = routeFile
        let mirror = MapOrientation.shouldMirrorMap(forRouteFile: routeFile)
        _mapFeatures = State(initialValue: MapDataLoader.loadMapFeatures(from: "testMap_Condition1", mirror180: mirror, routeFile: routeFile))
        _routes = State(initialValue: RouteMapDataLoader.loadRouteFeatures(from: routeFile, mirror180: mirror))
    }

    var body: some View {
        RouteMapView(
            features: mapFeatures,
            routes: routes,
            isInteractionEnabled: true,
            zoomableIntersectionIDs: routeIntersectionIDs,
            rotateMap180: false,
            onThreeFingerSwipe: {
                performBackNavigation()
            },
            onIntersectionDoubleTap: { intersection in
                holdSessionForIntersection = true
                intersectionZoomSelection = IntersectionZoomSelection(id: intersection.id)
            }
        )
        .ignoresSafeArea(.container)
        .navigationBarTitle(title, displayMode: .inline)
        .navigationBarBackButtonHidden(false)
        .navigationDestination(item: $intersectionZoomSelection) { selection in
            IntersectionDetailView(
                intersection: intersectionFeature(id: selection.id),
                routeFile: routeFile,
                routeTitle: title
            )
        }
        .onAppear {
            setupView()
            announceMapOverviewIfNeeded()
            DataService.shared.startSession(routeTitle: title, routeFile: routeFile)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            announceScreenIntroIfNeeded()
        }
        .onChange(of: intersectionZoomSelection) { _, newValue in
            if newValue == nil {
                holdSessionForIntersection = false
                AccessibleMapView.suppressVoiceOverLayoutFocus = true
                hasAnnouncedMapOverviewThisVisit = false
                announceMapOverviewIfNeeded()
            }
        }
        .onDisappear {
            let leavingRoute = intersectionZoomSelection == nil && !holdSessionForIntersection
            if leavingRoute {
                DataService.shared.endSession()
            }
            FeedbackManager.shared.stopAllFeedback()
        }
        .accessibilityAction(.escape) {
            performBackNavigation()
        }
        .disableInteractivePopGesture()
    }

    private func intersectionFeature(id: String) -> IntersectionFeature {
        mapFeatures.compactMap { $0 as? IntersectionFeature }.first { $0.id == id }!
    }

    private var routeIntersectionIDs: Set<String> {
        Set(routes.flatMap { $0.waypoints })
    }

    private func setupView() {
        FeedbackManager.shared.presentationMode = .naturalLanguage

        let mirror = MapOrientation.shouldMirrorMap(forRouteFile: routeFile)
        if mapFeatures.isEmpty {
            mapFeatures = MapDataLoader.loadMapFeatures(from: baseMapFile, mirror180: mirror, routeFile: routeFile)
        }
        if routes.isEmpty {
            routes = RouteMapDataLoader.loadRouteFeatures(from: routeFile, mirror180: mirror)
        }

        print("Loaded \(mapFeatures.count) map features and \(routes.count) route(s)")
        if let route = routes.first {
            print("Route waypoints: \(route.waypoints)")
        }

        if UIAccessibility.isVoiceOverRunning, !hasAnnouncedScreenIntro {
            announceScreenIntroIfNeeded()
        }
    }

    private func announceMapOverviewIfNeeded() {
        guard !hasAnnouncedMapOverviewThisVisit else { return }
        hasAnnouncedMapOverviewThisVisit = true
        MapViewAnnouncement.announce(MapViewAnnouncement.mapOverview)
    }

    private func announceScreenIntroIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning, !hasAnnouncedScreenIntro else { return }
        hasAnnouncedScreenIntro = true
        MapViewAnnouncement.announce(MapViewAnnouncement.mapOverview)
    }

    private func performBackNavigation() {
        DataService.shared.endSession()
        FeedbackManager.shared.stopAllFeedback()
        presentationMode.wrappedValue.dismiss()
    }
}

#Preview {
    NavigationView {
        RouteStudyView()
    }
}
