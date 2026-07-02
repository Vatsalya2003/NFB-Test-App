// FeedbackManager.swift
// Central hub — calls HapticService + SpeechService when user touches map features.
// Use FeedbackManager.shared from anywhere instead of calling haptics directly.

import SenseKit
import AVFoundation
import UIKit

@MainActor  
class FeedbackManager {
    static let shared = FeedbackManager()
    
    let hapticService = HapticService.shared
    private let audioService: AudioService
    private let speechService: SpeechService
    
    // State tracking
    var isPlayingContinuousSound = false
    private var isPulsingHaptic = false
    private(set) var isCrosswalkPulsing = false
    private var isCrosswalkAudioActive = false
    var isRouteOverCrosswalkFeedback = false
    var isStreetOverCrosswalkFeedback = false
    private var routeTurnDingWorkItem: DispatchWorkItem?
    private var routeTurnRepeatingTimer: Timer?
    private(set) var isRouteTurnDingActive = false
    
    var presentationMode: LandmarkPresentationMode {
        get { speechService.presentationMode }
        set { speechService.presentationMode = newValue }
    }
    
    private init() {
        self.audioService = AudioService()
        self.speechService = SpeechService()
    }
    
    func provideLandmarkFeedback(_ landmark: LandmarkFeature) {
        provideLandmarkFeedback(landmark, isAnchorPoint: false)
    }
    
    func provideLandmarkFeedback(_ landmark: LandmarkFeature, isAnchorPoint: Bool) {
        let name = landmark.properties["name"] as? String ?? "landmark"
        let category = landmark.properties["category"] as? String ?? "generic"
        let side = landmark.properties["side"] as? String ?? "center"
        
        let feedbackType = isAnchorPoint ? "anchor point" : "direct landmark"
        print("FeedbackManager: Providing \(feedbackType) feedback for \(name)")
        
        hapticService.playSingleTap()
        
        speechService.announceLandmark(
            name: name,
            category: category,
            side: side,
            mode: presentationMode,
            isAnchorPoint: isAnchorPoint
        )
        
        print("FeedbackManager: Triggered both haptic and audio for \(feedbackType): \(name)")
    }

    func provideCorridorFeedback(_ corridor: CorridorFeature) {
        let name = corridor.properties["name"] as? String ?? "corridor"
        speechService.announceCorridor(name: name)
    }
    
    func provideIntersectionFeedback(_ intersection: IntersectionFeature) {
        hapticService.playSingleTap()
    }

    // MARK: - For Roads (Heavy buzz) and Sidewalks (Street continuous)

    private var continuousVibrationStyle: HapticService.ContinuousVibrationStyle?

    /// Level 1 corridors and Level 2 blue roads — heavy buzz.
    func startHeavyBuzzFeedback() {
        startContinuousVibration(style: .heavyBuzz)
    }

    /// Level 2 gray sidewalks — softer “street” continuous rumble.
    func startStreetFeedback() {
        startContinuousVibration(style: .street)
    }

    private func startContinuousVibration(style: HapticService.ContinuousVibrationStyle) {
        if isPlayingContinuousSound, continuousVibrationStyle == style {
            return
        }

        stopContinuousPulsing()
        stopCrosswalkFeedback()

        if isPlayingContinuousSound {
            hapticService.stopContinuousVibration()
        }

        isPlayingContinuousSound = true
        continuousVibrationStyle = style
        hapticService.startContinuousVibration(style: style)
        print("Started \(style) continuous vibration")
    }

    /// Alias for roads on the route overview map.
    func startContinuousSound(intensityScale: Float = 1.0) {
        _ = intensityScale
        startHeavyBuzzFeedback()
    }

    func stopContinuousSound() {
        isPlayingContinuousSound = false
        continuousVibrationStyle = nil
        hapticService.stopContinuousVibration()
        print("Stopped corridor/sidewalk vibration")
    }
    
    // MARK: - For Intersections (Pulsing vibration + Ding, NO SPEECH)
    func startContinuousPulsing() {
        if isPulsingHaptic {
            print("Already pulsing")
            return
        }
        
        stopContinuousSound()
        stopCrosswalkFeedback()
        
        isPulsingHaptic = true
        hapticService.startVertexFeedback()
        
        print("Started haptic pulsing + ding for intersection")
    }
    
    // MARK: - For Landmarks (Faster pulsing vibration + SPEECH)
    func startLandmarkPulsing() {
        if isPulsingHaptic {
            print("Already pulsing")
            return
        }
        
        stopContinuousSound()
        stopCrosswalkFeedback()
        
        isPulsingHaptic = true
        hapticService.startFastPulsingVibration()
        
        print("Started haptic pulsing for landmark (fast pulse)")
    }
    
    func stopContinuousPulsing() {
        isPulsingHaptic = false
        hapticService.stopVertexFeedback()
        print("Stopped pulsing + ding")
    }

    // MARK: - For Crosswalks (tic-tic-tic haptics + tick sounds)
    private var crosswalkTickTimer: Timer?

    func startCrosswalkFeedback() {
        if isCrosswalkPulsing {
            return
        }

        stopContinuousSound()
        stopContinuousPulsing()
        stopRoutePulsing()
        isRouteOverCrosswalkFeedback = false

        isCrosswalkPulsing = true
        hapticService.startCrosswalkPulsing()
        startCrosswalkAudioTicks()

        print("Started crosswalk tic-tic feedback")
    }

    /// Crosswalk tick audio only — used when route haptics take priority on a shared crosswalk.
    func startCrosswalkAudioTicks() {
        isCrosswalkAudioActive = true
        audioService.playCrosswalkTick()
        crosswalkTickTimer?.invalidate()
        crosswalkTickTimer = Timer.scheduledTimer(withTimeInterval: 0.17, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCrosswalkPulsing || self.isCrosswalkAudioActive else { return }
                self.audioService.playCrosswalkTick()
            }
        }
    }

    func stopCrosswalkAudioTicks() {
        isCrosswalkAudioActive = false
        crosswalkTickTimer?.invalidate()
        crosswalkTickTimer = nil
        audioService.stopCrosswalkAudio()
    }

    func stopCrosswalkFeedback() {
        guard isCrosswalkPulsing || isCrosswalkAudioActive else { return }
        isCrosswalkPulsing = false
        isRouteOverCrosswalkFeedback = false
        isStreetOverCrosswalkFeedback = false
        hapticService.stopCrosswalkPulsing()
        stopCrosswalkAudioTicks()
        print("Stopped crosswalk feedback")
    }

    /// Route pulsing haptics plus crosswalk tick audio (no crosswalk haptics).
    func startRouteOverCrosswalkFeedback() {
        stopContinuousSound()
        stopContinuousPulsing()
        hapticService.stopCrosswalkPulsing()
        isCrosswalkPulsing = false
        isStreetOverCrosswalkFeedback = false

        if !isCrosswalkAudioActive {
            startCrosswalkAudioTicks()
        }
        isRouteOverCrosswalkFeedback = true
        hapticService.startRouteVibration()
        print("Started route-over-crosswalk feedback (route haptics + crosswalk audio)")
    }

    /// Street heavy-buzz haptics plus crosswalk tick audio (no crosswalk haptics).
    /// Used when a crosswalk overlaps a corridor — user feels the street underneath + hears clicks.
    func startStreetOverCrosswalkFeedback() {
        stopContinuousPulsing()
        stopRoutePulsing()
        hapticService.stopCrosswalkPulsing()
        isCrosswalkPulsing = false
        isRouteOverCrosswalkFeedback = false

        isStreetOverCrosswalkFeedback = true
        isPlayingContinuousSound = true
        continuousVibrationStyle = .heavyBuzz
        hapticService.startContinuousVibration(style: .heavyBuzz)

        startCrosswalkAudioTicks()
        print("Started street-over-crosswalk feedback (street haptics + crosswalk audio)")
    }
    
    // MARK: - Single Pulse (for taps)
    func playPulseHaptic() {
        hapticService.playSingleTap()
        print("Single pulse haptic")
    }

    func playRouteTurnDing() {
        audioService.playRouteTurnDing()
        hapticService.playRouteTurnHapticTap()
        print("Route turn ding")
    }

    /// Stops crosswalk/route/speech haptics first, then plays the turn ding once it is audible.
    func playRouteTurnDingOnce() {
        routeTurnDingWorkItem?.cancel()

        crosswalkTickTimer?.invalidate()
        crosswalkTickTimer = nil
        isCrosswalkPulsing = false
        isCrosswalkAudioActive = false
        isRouteOverCrosswalkFeedback = false
        audioService.stopCrosswalkAudio()
        hapticService.stopCrosswalkPulsing()

        stopRoutePulsing()
        stopContinuousSound()
        stopContinuousPulsing()
        speechService.stopAllFeedback()
        hapticService.stopAllHaptics()
        isPlayingContinuousSound = false
        isPulsingHaptic = false
        continuousVibrationStyle = nil

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.audioService.playRouteTurnDing()
            self.hapticService.playRouteTurnHapticTap()
            print("Route turn ding (exclusive)")
        }
        routeTurnDingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    
    // MARK: - Repeating Route Turn Ding (while finger stays on dot)

    func startRouteTurnFeedback() {
        guard !isRouteTurnDingActive else { return }

        stopCrosswalkFeedback()
        stopRoutePulsing()
        stopContinuousSound()
        stopContinuousPulsing()
        speechService.stopAllFeedback()

        isRouteTurnDingActive = true

        audioService.playRouteTurnDing()
        hapticService.playRouteTurnHapticTap()

        routeTurnRepeatingTimer?.invalidate()
        routeTurnRepeatingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRouteTurnDingActive else { return }
                self.audioService.playRouteTurnDing()
                self.hapticService.playRouteTurnHapticTap()
            }
        }
        print("Started repeating route turn ding")
    }

    func stopRouteTurnFeedback() {
        isRouteTurnDingActive = false
        routeTurnRepeatingTimer?.invalidate()
        routeTurnRepeatingTimer = nil
    }

    // MARK: - Speech (Direct method using AudioService)
    func speak(_ text: String) {
        audioService.speak(text)
        print("Speaking: \(text)")
    }
    
    func speakWithStudyPosition(_ text: String, side: String) {
        switch side.lowercased() {
        case "left":
            audioService.speakSpatially(text, at: AVAudio3DPoint(x: -5, y: 0, z: 0))
        case "right":
            audioService.speakSpatially(text, at: AVAudio3DPoint(x: 5, y: 0, z: 0))
        default:
            audioService.speak(text)
        }
    }
    
    // MARK: - Complete cleanup
    func stopAllFeedback() {
        routeTurnDingWorkItem?.cancel()
        routeTurnDingWorkItem = nil
        routeTurnRepeatingTimer?.invalidate()
        routeTurnRepeatingTimer = nil
        crosswalkTickTimer?.invalidate()
        crosswalkTickTimer = nil
        audioService.stopCrosswalkAudio()
        hapticService.stopAllHaptics()
        speechService.stopAllFeedback()

        isPlayingContinuousSound = false
        isPulsingHaptic = false
        isCrosswalkPulsing = false
        isCrosswalkAudioActive = false
        isRouteOverCrosswalkFeedback = false
        isStreetOverCrosswalkFeedback = false
        isRouteTurnDingActive = false
        continuousVibrationStyle = nil

        print("Stopped ALL feedback")
    }
    
    func resetAllSystems() {
        print("Resetting feedback systems...")
        stopAllFeedback()
        print("Reset complete")
    }
    
    func handleAppBackground() {
        hapticService.handleAppBackground()
    }
    
    func handleAppForeground() {
        hapticService.handleAppForeground()
    }
}
