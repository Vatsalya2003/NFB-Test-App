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

    // MARK: - For Corridors (Continuous vibration - NO SPEECH)
    func startContinuousSound() {
        if isPlayingContinuousSound {
            print("Already playing continuous vibration")
            return
        }
        
        stopContinuousPulsing()
        
        isPlayingContinuousSound = true
        hapticService.startContinuousVibration()
        
        print("Started corridor continuous vibration")
    }
    
    func stopContinuousSound() {
        isPlayingContinuousSound = false
        hapticService.stopContinuousVibration()
        print("Stopped corridor vibration")
    }
    
    // MARK: - For Intersections (Pulsing vibration + Ding, NO SPEECH)
    func startContinuousPulsing() {
        if isPulsingHaptic {
            print("Already pulsing")
            return
        }
        
        stopContinuousSound()
        
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
        
        isPulsingHaptic = true
        hapticService.startFastPulsingVibration()
        
        print("Started haptic pulsing for landmark (fast pulse)")
    }
    
    func stopContinuousPulsing() {
        isPulsingHaptic = false
        hapticService.stopVertexFeedback()
        print("Stopped pulsing + ding")
    }
    
    // MARK: - Single Pulse (for taps)
    func playPulseHaptic() {
        hapticService.playSingleTap()
        print("Single pulse haptic")
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
        hapticService.stopAllHaptics()
        speechService.stopAllFeedback()
        
        isPlayingContinuousSound = false
        isPulsingHaptic = false
        
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
