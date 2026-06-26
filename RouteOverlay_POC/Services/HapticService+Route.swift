import CoreHaptics
import UIKit

/// Extension to HapticService for route-specific haptic patterns
extension HapticService {
    
    // MARK: - Route Vibration Pattern
    
    /// Route vibration: rhythmic pulsing (distinct from corridor's steady continuous hum).
    /// Streets = steady continuous ~78%; route = rhythmic pulse at 100%.
    func startRouteVibration() {
        guard let engine = hapticEngine else {
            print("No haptic engine for route vibration")
            return
        }

        stopContinuousVibration()
        stopPulsingVibration()
        stopRouteVibration()
        stopCrosswalkPulsing()

        let pulseInterval: TimeInterval = 0.2
        let pulseDuration: TimeInterval = 0.12
        let routeIntensity: Float = 1.0
        let routeSharpness: Float = 0.85

        do {
            try engine.start()

            var events: [CHHapticEvent] = []
            for i in 0..<50 {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: routeIntensity)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: routeSharpness)
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [intensity, sharpness],
                    relativeTime: TimeInterval(i) * pulseInterval,
                    duration: pulseDuration
                ))
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            routePlayer = try engine.makeAdvancedPlayer(with: pattern)
            routePlayer?.loopEnabled = true
            try routePlayer?.start(atTime: CHHapticTimeImmediate)

            print("✅ Started route vibration: rhythmic pulse (vs corridor continuous)")

        } catch {
            print("❌ Failed to start route vibration: \(error)")
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.prepare()
            impact.impactOccurred()
        }
    }
}
