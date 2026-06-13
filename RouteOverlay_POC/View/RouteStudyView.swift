// RouteStudyView.swift
// Loads the base map + one route file, then shows RouteMapView full screen.

import SwiftUI
import MapKit

/// Main study view for Route Overlay proof-of-concept
/// Uses Natural Language as base modality (per study design)
struct RouteStudyView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mapFeatures: [MapFeature] = []
    @State private var routes: [RouteFeature] = []
    @State private var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    
    // Route configuration
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
    }
    
    private func setupView() {
        // Set to Natural Language mode (base modality for route study)
        FeedbackManager.shared.presentationMode = .naturalLanguage
        
        // Load base map (corridors + intersections + landmarks) and the selected route overlay.
        mapFeatures = MapDataLoader.loadMapFeatures(from: baseMapFile)
        routes = RouteMapDataLoader.loadRouteFeatures(from: routeFile)
        
        print("Loaded \(mapFeatures.count) map features and \(routes.count) route(s)")
        
        if UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let message = "Navigation map. Blue lines show streets. Touch roads for vibration feedback."
                UIAccessibility.post(notification: .screenChanged, argument: message)
            }
        }
    }
    
    private func performBackNavigation() {
        FeedbackManager.shared.stopAllFeedback()
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        RouteStudyView()
    }
}
