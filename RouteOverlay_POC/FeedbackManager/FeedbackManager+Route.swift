import Foundation
import AVFoundation

/// Extension to FeedbackManager for route-specific feedback
/// This adds route overlay haptic patterns differentiated from corridor feedback
extension FeedbackManager {
    
    // MARK: - Route-Specific Haptic Feedback
    
    /// Start route pulsing vibration - DIFFERENT pattern from corridor
    /// Route: Faster, rhythmic pulsing (feels like "walking guidance")
    /// Corridor: Continuous steady vibration (feels like "on path")
    func startRoutePulsing() {
        if isPlayingContinuousSound {
            print("Stopping corridor vibration for route")
            stopContinuousSound()
        }
        
        // Use the existing pulsing but with route-specific parameters
        // In a full implementation, HapticService would have a separate route pattern
        hapticService.startRouteVibration()
        print("Started route pulsing vibration")
    }
    
    func stopRoutePulsing() {
        hapticService.stopRouteVibration()
        print("Stopped route pulsing")
    }
    
    // MARK: - Dual-Layer Feedback Control
    
    /// Handle overlapping corridor + route touch
    /// Priority: Route > Corridor (route guidance takes precedence)
    func handleDualLayerTouch(onCorridor: Bool, onRoute: Bool, routeFeature: RouteFeature?) {
        if onRoute, let route = routeFeature {
            // Route takes priority - pulsing vibration
            startRoutePulsing()
            speak("On route")
            print("Dual layer: Route priority - \(route.routeName)")
        } else if onCorridor {
            // Corridor only - continuous vibration
            startContinuousSound()
            print("Dual layer: Corridor only")
        } else {
            // Off both - stop all
            stopAllFeedback()
            print("Dual layer: Off path")
        }
    }
    
    // MARK: - Route Navigation Announcements
    
    /// Announce route waypoint/instruction
    func announceRouteWaypoint(instruction: String) {
        speak(instruction)
        playPulseHaptic()
        print("Route waypoint: \(instruction)")
    }
    
    /// Announce route start
    func announceRouteStart(routeName: String, totalDistance: Double) {
        let announcement = "Starting route: \(routeName), \(Int(totalDistance)) feet total"
        speak(announcement)
        print("Route start: \(announcement)")
    }
    
    /// Announce route completion
    func announceRouteComplete(destination: String) {
        speak("Arrived at \(destination)")
        // Special haptic pattern for arrival
        hapticService.playSingleTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.hapticService.playSingleTap()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.hapticService.playSingleTap()
        }
        print("Route complete: \(destination)")
    }
}
