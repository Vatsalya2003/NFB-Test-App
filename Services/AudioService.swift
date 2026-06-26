//
//  AudioService.swift
//  Plays spatial audio and routes text-to-speech through SpeechSynthesizerManager.
//

import Foundation
import AVFoundation
import UIKit
import AudioToolbox
import SenseKit

@MainActor
class AudioService: NSObject {
    // MARK: - Core Components
    private let audioEngine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let audioPlayerNode = AVAudioPlayerNode()
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var speechManager = SpeechSynthesizerManager()

    // MARK: - Sound Effect Players
    private var soundEffectPlayers: [String: AVAudioPlayer] = [:]
    private var spatialSoundPlayers: [String: AVAudioPlayerNode] = [:]
    private var activeSpatialNodes: [AVAudioPlayerNode] = []
    
    // MARK: - State
    private var isEngineRunning = false
    private var lastPlayTime: Date?
    private var routeTurnDingEngine: AVAudioEngine?
    private var routeTurnDingPlayer: AVAudioPlayerNode?
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        // Configure audio session for spatial audio
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            
            // Enable spatial audio if available
            if #available(iOS 14.0, *) {
                try session.setSupportsMultichannelContent(true)
            }
            
            try session.setActive(true)
            print("Audio session configured for speech and spatial audio")
            print("Spatial audio support: \(session.category), mode: \(session.mode)")
        } catch {
            print("Audio session error: \(error)")
        }
        
        self.speechSynthesizer = AVSpeechSynthesizer()
        self.speechSynthesizer.delegate = self  // Set delegate
        
        // Setup interruption handling
        setupAudioSessionInterruptionHandling()
        
        setupAudioEngine()
        loadSoundEffects()
    }
    
    // MARK: - Audio Session Interruption Handling
    private func setupAudioSessionInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("Audio session interrupted")
            // Audio has been interrupted
            
        case .ended:
            print("Audio session interruption ended")
            // Reactivate audio session
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                // Restart engine if needed
                if !audioEngine.isRunning {
                    try audioEngine.start()
                }
            } catch {
                print("Failed to reactivate audio session: \(error)")
            }
            
        @unknown default:
            break
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(environment)
        audioEngine.attach(audioPlayerNode)
        
        // CRITICAL: Use mono format for spatial audio
        let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 22050.0,
                                       channels: 1,  // MONO for spatialization
                                       interleaved: false)!
        
        // Configure for spatial
        audioPlayerNode.renderingAlgorithm = .HRTFHQ
        audioPlayerNode.sourceMode = .spatializeIfMono
        
        environment.renderingAlgorithm = .HRTFHQ
        environment.sourceMode = .spatializeIfMono
        environment.distanceAttenuationParameters.distanceAttenuationModel = .exponential
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.smallRoom)
        environment.reverbParameters.level = 0.7
        
        // Connect with mono format
        audioEngine.connect(audioPlayerNode, to: environment, format: monoFormat)
        audioEngine.connect(environment, to: audioEngine.mainMixerNode, format: nil)
        
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        
        do {
            try audioEngine.start()
            isEngineRunning = true
            print("Spatial audio engine started with mono format")
        } catch {
            print("Failed to start engine: \(error)")
        }
    }
    
    // MARK: - Sound Effects Loading
    private func loadSoundEffects() {
        let soundFiles = [
            "toilet_flush": "toilet_flush",
            "stairway": "stairway",
            "conference_room": "conference_room",
            "vending_machine": "vending_machine",
            "door_knock": "door_knock", 
            "water_running": "water_running",
            "kitchen": "kitchen",
            "elevator": "elevator",
            "birdtweet": "birdtweet",
            "catmeow": "catmeow",
            "dogbark": "dogbark"
        ]
        
        print("Loading sound effects...")
        for (key, filename) in soundFiles {
            if let url = Bundle.main.url(forResource: filename, withExtension: "mp3") {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    soundEffectPlayers[key] = player
                    print("Loaded sound effect: \(key) -> \(filename).mp3")
                } catch {
                    print("Failed to load sound effect \(key): \(error)")
                }
            } else {
                print("Could not find audio file: \(filename).mp3")
            }
        }
        
        print("Total sound effects loaded: \(soundEffectPlayers.count)")
    }
    
    // MARK: - Position Calculation
    func positionForLandmarkSide(_ side: String) -> AVAudio3DPoint {
        switch side.lowercased() {
        case "left":
            return AVAudio3DPoint(x: -5, y: 0, z: 0)
        case "right":
            return AVAudio3DPoint(x: 5, y: 0, z: 0)
        case "ahead", "front":
            return AVAudio3DPoint(x: 0, y: 0, z: -3)
        case "behind", "back":
            return AVAudio3DPoint(x: 0, y: 0, z: 3)
        default:
            return AVAudio3DPoint(x: 0, y: 0, z: 0)
        }
    }
    
    // MARK: - Volume Control
    private func getVolumeForSoundEffect(_ soundKey: String) -> Float {
        switch soundKey.lowercased() {
        case "stairway":
            return 1.0  // Normal volume
        case "vending_machine":
            return 1.0  // Normal volume
        case "toilet_flush":
            return 1.0  // Normal volume
        case "door_knock":
            return 1.0  // Normal volume
        case "water_running":
            return 1.0  // Normal volume
        case "conference_room":
            return 1.0  // Normal volume
        default:
            return 1.0  // Default normal volume
        }
    }
    
    // MARK: - Regular Speech (Condition 1)
    func speak(_ text: String) {
        print("AudioService: Starting speech: '\(text)'")

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        
        // Always stop previous speech to ensure new speech plays
        if speechSynthesizer.isSpeaking {
            print("AudioService: Stopping previous speech to speak new text")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Execute speech immediately without delay to prevent race conditions
        executeSpeech(text)
    }
    
    private func executeSpeech(_ text: String) {
        // Ensure audio session is properly configured before speaking
        do {
            let session = AVAudioSession.sharedInstance()
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
                print("AudioService: Audio session activated for speech")
            } else {
                print("AudioService: Other audio playing, proceeding with current session")
            }
        } catch {
            print("AudioService: Failed to activate audio session for speech: \(error)")
            // Continue anyway, might still work
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1  // Slightly faster
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        speechSynthesizer.speak(utterance)
        print("AudioService: Speech command sent to synthesizer")
    }
    
    // MARK: - Spatial Speech (Condition 2)
    func speakSpatially(_ text: String, at position: AVAudio3DPoint) {
        print("AudioService: Starting spatial speech: '\(text)' at x:\(position.x)")

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        
        // Always stop previous speech to ensure new speech plays
        if speechSynthesizer.isSpeaking {
            print("AudioService: Stopping previous spatial speech")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Execute spatial speech immediately without delay to prevent race conditions
        executeSpatialSpeech(text, at: position)
    }
    
    private func executeSpatialSpeech(_ text: String, at position: AVAudio3DPoint) {
        // Ensure engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start engine: \(error)")
                speak(text) // Fallback
                return
            }
        }
        
        // CRITICAL: Set position BEFORE playing
        audioPlayerNode.position = position
        audioPlayerNode.renderingAlgorithm = .HRTFHQ
        audioPlayerNode.sourceMode = .spatializeIfMono
        audioPlayerNode.volume = 1.0
        
        // Use your SpeechSynthesizerManager
        speechManager.speak(text: text, audioPlayerNode: audioPlayerNode)
        
        print("AudioService: Spatial speech command sent: '\(text)' at position (x: \(position.x))")
    }
    
    // MARK: - Spatial Sound Effects (Condition 3)
    func playSpatialSoundEffect(_ soundKey: String, at position: AVAudio3DPoint) {
        print("AudioService: Starting spatial sound effect: \(soundKey) at x:\(position.x)")
        
        // Stop any currently playing speech to ensure sound effect plays
        if speechSynthesizer.isSpeaking {
            print("AudioService: Stopping speech for sound effect")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let extensions = ["mp3", "m4a", "flac"]
        var audioURL: URL? = nil
        var foundExtension: String? = nil
        
        for ext in extensions {
            if let url = Bundle.main.url(forResource: soundKey, withExtension: ext) {
                audioURL = url
                foundExtension = ext
                break
            }
        }
        
        guard let url = audioURL,
            let file = try? AVAudioFile(forReading: url) else {
            print("Could not load: \(soundKey) with any supported format")
            return
        }
        
        // Ensure engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
                return
            }
        }
        
        // Stop previous playback to ensure clean state
        audioPlayerNode.stop()
        audioPlayerNode.reset()
            
            // Set spatial position and volume
            audioPlayerNode.position = position
            audioPlayerNode.renderingAlgorithm = .HRTFHQ
            audioPlayerNode.volume = getVolumeForSoundEffect(soundKey)
            
            // Get the output format of the player node (should be mono)
            let playerFormat = audioPlayerNode.outputFormat(forBus: 0)
            
            // Create buffer with the FILE'S format first
            guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, 
                                                    frameCapacity: AVAudioFrameCount(file.length)) else {
                return
            }
            
            try? file.read(into: fileBuffer)
            
            // If formats don't match, convert
            let bufferToPlay: AVAudioPCMBuffer
            if file.processingFormat.channelCount != playerFormat.channelCount {
                // Need to convert stereo to mono
                guard let converter = AVAudioConverter(from: file.processingFormat, to: playerFormat),
                    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: playerFormat, 
                                                            frameCapacity: AVAudioFrameCount(file.length)) else {
                    print("❌ Failed to create converter")
                    return
                }
                
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return fileBuffer
                }
                
                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
                
                if let error = error {
                    print("❌ Conversion error: \(error)")
                    return
                }
                
                bufferToPlay = convertedBuffer
            } else {
                bufferToPlay = fileBuffer
            }
            
            // Schedule and play
            audioPlayerNode.scheduleBuffer(bufferToPlay, at: nil, options: .interrupts, completionHandler: nil)
            
            if !audioPlayerNode.isPlaying {
                audioPlayerNode.play()
            }
            
            print("AudioService: Successfully playing spatial sound: \(soundKey) at x:\(position.x)")
            lastPlayTime = Date()
}
    
    private func playFallbackSound(_ soundKey: String) {
        guard let player = soundEffectPlayers[soundKey] else {
            print("Fallback sound effect not found: \(soundKey)")
            return
        }
        print("Playing fallback (non-spatial) sound: \(soundKey)")
        player.play()
    }
        // MARK: - Helper Methods
        func stopSpeaking() {
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
    }
    
    func stopAllAudio() {
        stopSpeaking()
        audioPlayerNode.stop()
        
        for player in soundEffectPlayers.values {
            player.stop()
        }
        
        for node in spatialSoundPlayers.values {
            node.stop()
        }
    }
    
    func prepare() {
        // Ensure audio session is configured
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Route Turn Ding

    /// Short metallic ding for orange route-turn dots. Uses a synthesized tone because
    /// `AudioServicesPlaySystemSound` is often silent under the spoken-audio session.
    func playRouteTurnDing() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            routeTurnDingEngine?.stop()
            routeTurnDingEngine = nil
            routeTurnDingPlayer = nil

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let sampleRate = 44_100.0
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let duration = 0.14
            let frequency = 1_050.0
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                AudioServicesPlayAlertSound(1_057)
                return
            }
            buffer.frameLength = frameCount

            let samples = buffer.floatChannelData![0]
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                let attack = min(t / 0.008, 1.0)
                let decay = exp(-max(t - 0.008, 0) * 20)
                samples[i] = Float(sin(2.0 * Double.pi * frequency * t) * attack * decay * 0.55)
            }

            engine.mainMixerNode.outputVolume = 1.0
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak engine] in
                DispatchQueue.main.async {
                    engine?.stop()
                }
            }
            player.play()

            routeTurnDingEngine = engine
            routeTurnDingPlayer = player
        } catch {
            print("AudioService: Route turn ding failed (\(error)), falling back to system sound")
            AudioServicesPlayAlertSound(1_057)
        }
    }
}

// MARK: - Helper Extension for PCMBuffer
extension AVAudioPCMBuffer {
    convenience init?(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        self.init(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        try file.read(into: self)
    }
}

extension AudioService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Speech started: '\(utterance.speechString)'")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech finished: '\(utterance.speechString)'")
    }
}
