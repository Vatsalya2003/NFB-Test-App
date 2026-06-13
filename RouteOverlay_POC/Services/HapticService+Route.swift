import CoreHaptics
import UIKit

/// Extension to HapticService for route-specific haptic patterns
extension HapticService {
    
    // MARK: - Route Vibration Pattern
    
    /// Route vibration: INTENSITY CONTRAST approach
    /// Route = 100% intensity continuous (strong, assertive)
    /// Corridor = 50% intensity continuous (softer)
    /// Users feel a clear "upgrade" when moving from corridor to route
    /// Same continuous feel, but noticeably STRONGER on route
    func startRouteVibration() {
        guard let engine = hapticEngine else {
            print("No haptic engine for route vibration")
            return
        }
        
        // Stop any existing vibrations first
        stopContinuousVibration()
        stopPulsingVibration()
        stopRouteVibration()
        
        do {
            // Ensure engine is running
            try engine.start()
            
            // Route uses FULL INTENSITY (100%) vs corridor's 50%
            // Higher sharpness (0.8) gives it a more assertive feel
            let routeIntensity: Float = 1.0    // 100% - double the corridor's 50%
            let routeSharpness: Float = 0.8    // Higher sharpness than corridor's 0.4
            let routeDuration: TimeInterval = 100.0  // Long continuous duration
            
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: routeIntensity
            )
            
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: routeSharpness
            )
            
            // Create a continuous event - same style as corridor but STRONGER
            let continuousEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: routeDuration
            )
            
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            
            // Use DEDICATED routePlayer (not continuousPlayer!)
            routePlayer = try engine.makeAdvancedPlayer(with: pattern)
            try routePlayer?.start(atTime: CHHapticTimeImmediate)
            
            print("✅ Started route vibration: CONTINUOUS at 100% intensity (vs corridor's 50%)")
            
        } catch {
            print("❌ Failed to start route vibration: \(error)")
            // Fallback to UIKit haptic
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.prepare()
            impact.impactOccurred()
        }
    }
}
