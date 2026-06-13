//
//  SpeechService.swift
//

import Foundation
import AVFoundation
import CoreHaptics

@MainActor
class SpeechService {
    // MARK: - Properties
    private let audioService: AudioService
    
    // Study configuration
    var presentationMode: LandmarkPresentationMode = .naturalLanguage
    private var announcedLandmarks: Set<String> = []
    
    // Enhanced tracking to differentiate anchor vs. direct landmark touches
    private var lastAnnouncementTime: Date?
    private var lastAnnouncedIdentifier: String?  // Tracks "landmarkID_anchor" or "landmarkID_direct"
    private let minTimeBetweenSameAnnouncements: TimeInterval = 0.5  // Only block if EXACT same type within 0.5s
    
    // MARK: - Initialization
    init() {
        self.audioService = AudioService()
    }
    
    // MARK: - Landmark Feedback
    func announceLandmark(
        name: String,
        category: String,
        side: String,
        mode: LandmarkPresentationMode? = nil,
        isAnchorPoint: Bool = false
    ) {
        // Use provided mode or default to current mode
        let activeMode = mode ?? presentationMode

        let announcementType = isAnchorPoint ? "anchor point" : "direct landmark"
        print("SpeechService: Starting \(announcementType) announcement")
        print("   Mode: \(activeMode)")
        print("   Name: \(name)")
        print("   Side: \(side)")
        print("   Is Anchor Point: \(isAnchorPoint)")
        
        // Create a unique identifier that includes whether it's anchor or direct
        let touchType = isAnchorPoint ? "anchor" : "direct"
        let fullIdentifier = "\(name)_\(side)_\(touchType)"
        
        // Smart debouncing: Only block if it's the EXACT SAME touch type within 0.5s
        // This allows: anchor → direct, direct → anchor transitions
        if let lastIdentifier = lastAnnouncedIdentifier,
           let lastTime = lastAnnouncementTime,
           lastIdentifier == fullIdentifier,  // Same exact touch type
           Date().timeIntervalSince(lastTime) < minTimeBetweenSameAnnouncements {
            print("SpeechService: Blocking duplicate \(touchType) touch (\(Date().timeIntervalSince(lastTime))s ago)")
            return
        }
        
        // Different touch type OR enough time passed - ALLOW
        print("SpeechService: Allowing audio (last: '\(lastAnnouncedIdentifier ?? "none")', current: '\(fullIdentifier)')")
        
        lastAnnouncementTime = Date()
        lastAnnouncedIdentifier = fullIdentifier
        
        // Execute audio immediately (no delays to prevent race conditions)
        print("SpeechService: Executing audio immediately")
        switch activeMode {
        case .practiceNL:
            print("   -> Using Natural Language for practice")
            announceNaturalLanguage(name: name, side: side, isAnchorPoint: isAnchorPoint)
        case .practiceSpatial:
            print("   -> Using Spatialized Audio for practice")
            announceSpatializedAudio(name: name, side: side, isAnchorPoint: isAnchorPoint)
        case .practiceIcons:
            print("   -> Using Auditory Icons for practice")
            announceSpatializedIcon(category: category, side: side, isAnchorPoint: isAnchorPoint)
        case .naturalLanguage:
            print("   -> Using Natural Language")
            announceNaturalLanguage(name: name, side: side, isAnchorPoint: isAnchorPoint)
            
        case .spatializedAudio:
            print("   -> Using Spatialized Audio")
            announceSpatializedAudio(name: name, side: side, isAnchorPoint: isAnchorPoint)
            
        case .spatializedIcons:
            print("   -> Using Auditory Icons")
            announceSpatializedIcon(category: category, side: side, isAnchorPoint: isAnchorPoint)
        }
        
        print("SpeechService: Completed landmark announcement for \(name)")
    }
    
    // MARK: - Condition 1: Natural Language
    private func announceNaturalLanguage(name: String, side: String, isAnchorPoint: Bool = false) {
        let announcement: String
        
        if isAnchorPoint {
            // Anchor points: Provide directional guidance
            let directionPhrase: String
            switch side.lowercased() {
            case "left":
                directionPhrase = ",left"
            case "right":
                directionPhrase = ",right"
            case "ahead", "front":
                directionPhrase = "ahead"
            case "behind", "back":
                directionPhrase = "behind"
            default:
                directionPhrase = "nearby"
            }
            announcement = "\(name) , \(directionPhrase)"
        } else {
            // Direct landmarks: Just announce the name
            announcement = name
        }
        
        audioService.speak(announcement)
        let feedbackType = isAnchorPoint ? "anchor point" : "direct landmark"
        print("Natural Language (\(feedbackType)): '\(announcement)'")
    }
    
    // MARK: - Condition 2: Spatialized Audio
    private func announceSpatializedAudio(name: String, side: String, isAnchorPoint: Bool = false) {
        let textToSpeak: String
        
        if isAnchorPoint {
            // Anchor points: Speak just the name from direction
            textToSpeak = name
        } else {
            // Direct landmarks: Speak just the name (no direction needed as you're touching it)
            textToSpeak = name
        }
        
        let position = audioService.positionForLandmarkSide(side)
        audioService.speakSpatially(textToSpeak, at: position)
        let feedbackType = isAnchorPoint ? "anchor point" : "direct landmark"
        print("Spatialized Audio (\(feedbackType)): '\(textToSpeak)' from \(side)")
    }
    
    // MARK: - Condition 3: Spatialized Icons
    private func announceSpatializedIcon(category: String, side: String, isAnchorPoint: Bool = false) {
        let soundKey = getSoundKeyForCategory(category)
        let position = audioService.positionForLandmarkSide(side)
        
        let feedbackType = isAnchorPoint ? "anchor point" : "direct landmark"
        print("CONDITION 3 DEBUG (\(feedbackType)):")
        print("   Category: '\(category)'")
        print("   Sound key: '\(soundKey)'")
        print("   Side: '\(side)'")
        print("   Position: (x: \(position.x), y: \(position.y), z: \(position.z))")
        
        // For spatialized icons, both anchor points and direct landmarks use the same sound
        // The spatial positioning provides the directional context
        audioService.playSpatialSoundEffect(soundKey, at: position)
        print("Spatialized Icon (\(feedbackType)): '\(soundKey)' sound from \(side)")
    }
    
    private func getSoundKeyForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "bathroom", "restroom":
            return "toilet_flush"
        case "kitchen":  
            return "kitchen"  
        case "water_fountain", "water":
            return "water_running"
        case "elevator", "lift":
            return "elevator"
        case "stairs", "stairway":
            return "stairway"
        case "conference_room", "conference", "meeting_room":
            return "conference_room"
        case "vending_machine", "vending":
            return "vending_machine"
        case "dog":
            return "dogbark"
        case "cat":
            return "catmeow"
        case "bird":
            return "birdtweet"
        default:
            return "door_knock"  // Default to door_knock instead of beep
        }
    }
    
    // MARK: - Corridor Feedback
    func announceCorridor(name: String) {
        // Simple announcement for entering a corridor
        audioService.speak("Entering \(name)")
        // Note: Haptic feedback handled by FeedbackManager
    }
    
    // MARK: - Intersection Feedback
    func announceIntersection(name: String, connectedCorridors: [String]) {
        let corridorList = connectedCorridors.joined(separator: " and ")
        let announcement = "\(name), connecting \(corridorList)"
        audioService.speak(announcement)
        // Note: Haptic feedback handled by FeedbackManager
    }
    
    // MARK: - State Management
    func resetAnnouncedLandmarks() {
        announcedLandmarks.removeAll()
        lastAnnouncementTime = nil
        lastAnnouncedIdentifier = nil
    }
    
    func hasAnnouncedLandmark(_ name: String) -> Bool {
        return announcedLandmarks.contains(name)
    }
    
    func stopAllFeedback() {
        audioService.stopAllAudio()
        // Note: Haptic stopping handled by FeedbackManager's HapticService
    }
}