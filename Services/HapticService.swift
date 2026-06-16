// HapticService.swift
// CoreHaptics engine — corridor continuous vibe, intersection slow pulse, landmark fast pulse.

import CoreHaptics
import AVFoundation
import AudioToolbox
import SenseKit
import UIKit

class HapticService {
    static let shared = HapticService()

    private var audioEngine: AVAudioEngine?
    //private var tonePlayer: AVAudioPlayerNode?
    private var pulseTimer: Timer?
    private var vertexDingTimer: Timer?
    
    // Vertex tracking
    var activeVertexIndex: Int?

    // MARK: - Properties
    var hapticEngine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    var pulsePlayer: CHHapticAdvancedPatternPlayer?
    var routePlayer: CHHapticAdvancedPatternPlayer?
    private var hapticController: HapticController?
    
    private let continuousDuration: TimeInterval = 100.0  // Very long duration
    
    // Intersection pulse timing (slower, more deliberate)
    private let pulseInterval: TimeInterval = 0.25    // 0.25 seconds between pulses
    private let pulseDuration: TimeInterval = 0.15    // 0.15 seconds pulse duration
    private let defaultIntensity: Float = 1.0         // Maximum intensity (for intersections/landmarks)
    private let defaultSharpness: Float = 0.5         // Medium sharpness
    
    // Corridor intensity (REDUCED to create contrast with route overlay)
    private let corridorIntensity: Float = 0.5        // 50% intensity for corridors
    private let corridorSharpness: Float = 0.5        // Lower sharpness for smooth feel
    
    // Landmark pulse timing (faster, snappier - 2x faster than intersections)
    private let landmarkPulseInterval: TimeInterval = 0.12   // 0.12s between pulses (vs 0.25s)
    private let landmarkPulseDuration: TimeInterval = 0.08   // 0.08s pulse duration (vs 0.15s)
    private let landmarkSharpness: Float = 0.7

    // State tracking
    private var isContinuousPlaying = false
    private var isPulsingPlaying = false
    private var supportsHaptics = false
    private var isControllerPrepared = false
    
    // MARK: - Diagnostic Tracking
    struct HapticDiagnostics {
        var startCount: Int = 0
        var stopCount: Int = 0
        var totalActiveTime: TimeInterval = 0
        var shortActivationCount: Int = 0  // < 50ms
        var avgActivationTime: TimeInterval = 0
        var activationTimes: [TimeInterval] = []
    }
    
    private var diagnostics = HapticDiagnostics()
    private var currentActivationStartTime: TimeInterval?
    private var lastCommandTime: TimeInterval = 0
    
    // MARK: - Initialization
    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        print("🎮 Device supports haptics: \(supportsHaptics)")

        setupHapticEngine()
        observeVoiceOverChanges()
    }

    private func observeVoiceOverChanges() {
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartEngine()
        }
    }

    
    // /// Check if device supports haptics
    // private func checkHapticCapability() {
    //     supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    //     print("🎮 Device supports haptics: \(supportsHaptics)")
    // }
    
    /// Setup the haptic engine
        private func setupHapticEngine() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    
        guard supportsHaptics else {
            print("Device doesn't support haptics")
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("Engine stopped: \(reason)")
                self?.restartEngine()
            }
            
            hapticEngine?.resetHandler = { [weak self] in
                self?.restartEngine()
            }
            
            try hapticEngine?.start()
            print("✅ Haptic engine started")
            
        } catch {
            print("❌ Failed to start engine: \(error)")
        }
    }
    
    /// Restart engine if it stops
    private func restartEngine() {
        do {
            try hapticEngine?.start()
            print("Haptic engine restarted")

        if isContinuousPlaying {
            isContinuousPlaying = false  // Reset flag
            startContinuousVibration()   // Restart
        }

        } catch {
            print("Failed to restart haptic engine: \(error)")
        }
    }
    
    // MARK: - Continuous Vibration (for Corridors)
    
    /// Start continuous vibration
    func startContinuousVibration() {
        let startTime = CACurrentMediaTime()
        let timeSinceLastCommand = startTime - lastCommandTime
        lastCommandTime = startTime
        
        guard supportsHaptics else {
            print("Device doesn't support haptics")
            return
        }
        
        if isContinuousPlaying {
            print("Continuous vibration already playing")
            return
        }
        
        do {
            // Stop any pulsing first
            stopPulsingVibration()
            
            // Ensure engine is running
            if hapticEngine?.currentTime == nil {
                try hapticEngine?.start()
            }
            
            // Create continuous haptic pattern with REDUCED intensity for corridors
            // This creates contrast with route overlay (which uses 100% intensity)
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: corridorIntensity  // 50% intensity for corridors
            )
            
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: corridorSharpness  // Lower sharpness for smooth feel
            )
            
            // Create a continuous event with long duration
            let continuousEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: continuousDuration  // 100 seconds
            )
            
            // Create pattern
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            
            // Create and start player
            continuousPlayer = try hapticEngine?.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            
            isContinuousPlaying = true
            
            // Track diagnostics
            currentActivationStartTime = startTime
            diagnostics.startCount += 1
            
            let commandDelay = timeSinceLastCommand * 1000  // in ms
            print("📳 START haptic: #\(diagnostics.startCount), delay since last cmd: \(String(format: "%.1f", commandDelay))ms")
            
        } catch {
            print("Failed to start continuous vibration: \(error)")
        }
    }
    
    /// Stop continuous vibration
    func stopContinuousVibration() {
        let stopTime = CACurrentMediaTime()
        let timeSinceLastCommand = stopTime - lastCommandTime
        lastCommandTime = stopTime
        
        isContinuousPlaying = false
        
        // Track diagnostics if we were playing
        if let startTime = currentActivationStartTime {
            let activationDuration = stopTime - startTime
            diagnostics.activationTimes.append(activationDuration)
            diagnostics.totalActiveTime += activationDuration
            
            if activationDuration < 0.05 {  // Less than 50ms
                diagnostics.shortActivationCount += 1
                print("⚠️ SHORT HAPTIC: Only \(String(format: "%.0f", activationDuration * 1000))ms (may not be felt)")
            }
            
            let commandDelay = timeSinceLastCommand * 1000  // in ms
            print("📳 STOP haptic: #\(diagnostics.stopCount + 1), duration: \(String(format: "%.0f", activationDuration * 1000))ms, delay since last cmd: \(String(format: "%.1f", commandDelay))ms")
            
            currentActivationStartTime = nil
        }
        
        diagnostics.stopCount += 1
        
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
            continuousPlayer = nil
        } catch {
            print("Failed to stop continuous vibration: \(error)")
        }
    }
    
    // MARK: - Pulsing Vibration (for Intersections/POIs)
    
    /// Start pulsing vibration
    func startPulsingVibration() {guard let engine = hapticEngine else { return }
        
        stopPulsingVibration()
        
        do {
            // Create pulsing pattern matching your specs
            var events: [CHHapticEvent] = []
            
            // Create pulses for ~10 seconds (20 pulses)
            // Each cycle is 0.5 seconds (pulse + gap)
            for i in 0..<20 {
                let intensity = CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: defaultIntensity  // 1.0
                )
                
                let sharpness = CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: defaultSharpness  // 0.5
                )
                
                // Create a continuous haptic for 0.15 seconds
                let pulseEvent = CHHapticEvent(
                    eventType: .hapticContinuous,  // Continuous for duration
                    parameters: [intensity, sharpness],
                    relativeTime: TimeInterval(i) * pulseInterval,  // Every 0.5 seconds
                    duration: pulseDuration  // 0.15 seconds long
                )
                
                events.append(pulseEvent)
            }
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            
            pulsePlayer = try engine.makeAdvancedPlayer(with: pattern)
            pulsePlayer?.loopEnabled = true  // Loop the pattern
            try pulsePlayer?.start(atTime: CHHapticTimeImmediate)
            
            print("✅ Started pulsing: 0.15s on, 0.35s off, repeating")
            
        } catch {
            print("❌ Failed to start pulsing: \(error)")
        }
    }
   

    func stopPulsingVibration() {
        do {
            try pulsePlayer?.stop(atTime: CHHapticTimeImmediate)
            pulsePlayer = nil
            print("Stopped pulsing")
        } catch {
            print("Failed to stop: \(error)")
        }
    }
    
    // MARK: - Fast Pulsing Vibration (for Landmarks - faster than intersections)
    
    /// Start fast pulsing vibration for landmarks
    /// 2x faster than intersection pulsing with higher sharpness for a "ticky" feel
    func startFastPulsingVibration() {
        guard let engine = hapticEngine else {
            print("No haptic engine available")
            return
        }
        
        // Stop any existing vibrations first
        stopPulsingVibration()
        stopContinuousVibration()
        
        do {
            // Ensure engine is running
            if engine.currentTime == nil {
                try engine.start()
            }
            
            var events: [CHHapticEvent] = []
            
            // Create fast pulsing pattern for landmarks
            // Each cycle is 0.12 seconds (pulse + gap) - 2x faster than intersection (0.25s)
            // Pulse duration: 0.08s (vs 0.15s for intersections)
            for i in 0..<80 {  // More pulses for same duration since they're faster
                let intensity = CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: defaultIntensity  // 1.0
                )
                
                let sharpness = CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: landmarkSharpness  // 0.7 - higher for "ticky" feel
                )
                
                // Create a continuous haptic for 0.08 seconds (shorter, snappier)
                let pulseEvent = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [intensity, sharpness],
                    relativeTime: TimeInterval(i) * landmarkPulseInterval,  // Every 0.12 seconds
                    duration: landmarkPulseDuration  // 0.08 seconds long
                )
                
                events.append(pulseEvent)
            }
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            
            pulsePlayer = try engine.makeAdvancedPlayer(with: pattern)
            pulsePlayer?.loopEnabled = true
            try pulsePlayer?.start(atTime: CHHapticTimeImmediate)
            
            print("✅ Started FAST landmark pulsing: 0.08s on, 0.04s off (2x faster than intersection)")
            
        } catch {
            print("❌ Failed to start fast pulsing: \(error)")
        }
    }
    
    // MARK: - Vertex Feedback (Pulsing Haptic + Ding Sound)
    
    /// Start vertex feedback - pulsing haptic with repeating ding sound
    func startVertexFeedback() {
        // Mark that we are actively on an intersection so repeating ding stays enabled.
        // We only need a non-nil sentinel value for timer gating.
        if activeVertexIndex == nil {
            activeVertexIndex = 0
        }
        
        // Prevent duplicate timers when this method is called repeatedly.
        vertexDingTimer?.invalidate()
        vertexDingTimer = nil
        
        startVertexPulsingHaptic()
        playVertexDing()
        vertexDingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard self?.activeVertexIndex != nil else { return }
            self?.playVertexDing()
        }
    }
    
    /// Start pulsing haptic specifically for vertices
    private func startVertexPulsingHaptic() {
        // Reuse the existing pulsing vibration for vertices
        startPulsingVibration()
    }
    
    /// Play the vertex ding sound
    private func playVertexDing() {
        AudioServicesPlaySystemSound(1057)
    }
    
    /// Stop vertex feedback - stops haptic and ding timer
    func stopVertexFeedback() {
        vertexDingTimer?.invalidate()
        vertexDingTimer = nil
        stopPulsingVibration()
        activeVertexIndex = nil
    }
    
    // MARK: - Single Tap
    
    /// Play single tap haptic
    func playSingleTap() {
        guard supportsHaptics else {
            // Fallback to simple impact
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred()
            return
        }
        
        do {
            // Ensure engine is running
            if hapticEngine?.currentTime == nil {
                try hapticEngine?.start()
            }
            
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 1.0
            )
            
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 1.0
            )
            
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            
            try player?.start(atTime: CHHapticTimeImmediate)
            print("Single tap haptic played")
            
        } catch {
            print("Failed to play single tap: \(error)")
            // Fallback
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred()
        }
    }
    
    // MARK: - Stop All
    
    func stopAllHaptics() {
        stopContinuousVibration()
        stopPulsingVibration()
        stopRouteVibration()
        stopVertexFeedback()
        print("Stopped all haptics")
    }
    
    /// Stop route vibration (called from extension)
    func stopRouteVibration() {
        do {
            try routePlayer?.stop(atTime: CHHapticTimeImmediate)
            routePlayer = nil
        } catch {
            print("Failed to stop route vibration: \(error)")
        }
    }
    
    // MARK: - App Lifecycle
    
    /// Call when app enters background
    func handleAppBackground() {
        stopAllHaptics()
        hapticEngine?.stop()
    }
    
    /// Call when app enters foreground
    func handleAppForeground() {
        if supportsHaptics {
            do {
                try hapticEngine?.start()
                print("Haptic engine restarted for foreground")
            } catch {
                print("Failed to restart haptic engine: \(error)")
            }
        }
    }
    
    // MARK: - Test Methods
    
    func testHaptics() {
        // Test single tap
        playSingleTap()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            // Test continuous for 2 seconds
            self?.startContinuousVibration()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.stopContinuousVibration()
                
                // Test pulsing for 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.startPulsingVibration()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.stopPulsingVibration()
                        print("Haptic test complete")
                    }
                }
            }
        }
    }
    
    // MARK: - Diagnostic Methods
    
    func getDiagnosticStats() -> HapticDiagnostics {
        var stats = diagnostics
        
        // Calculate average activation time
        if !stats.activationTimes.isEmpty {
            stats.avgActivationTime = stats.activationTimes.reduce(0, +) / TimeInterval(stats.activationTimes.count)
        }
        
        return stats
    }
    
    func resetDiagnostics() {
        diagnostics = HapticDiagnostics()
        currentActivationStartTime = nil
        lastCommandTime = 0
        print("🔄 Haptic diagnostics reset")
    }
}

