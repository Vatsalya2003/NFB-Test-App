//
//  SpeechSynthesizerManager.swift
//  Wraps AVSpeechSynthesizer — speaks text out loud for map feedback.
//

import AVFoundation
import Combine

class SpeechSynthesizerManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    var speechSynthesizer: AVSpeechSynthesizer
    var lastPlayedCircle: String? = nil

    private var finishCompletion: (() -> Void)?
    
    // Add strong reference to prevent deallocation
    private var currentBuffer: AVAudioPCMBuffer?
    private let bufferQueue = DispatchQueue(label: "audio.buffer.queue", qos: .userInitiated)

    override init() {
        self.speechSynthesizer = AVSpeechSynthesizer()
        super.init()
        self.speechSynthesizer.delegate = self
    }
    
    func speak(text: String,
               audioPlayerNode: AVAudioPlayerNode,
               completion: (() -> Void)? = nil) {
        
        // Stop any existing playback first
        audioPlayerNode.stop()
        audioPlayerNode.reset() // Clear any scheduled buffers
        
        // Ensure we're on the main thread for speech synthesis
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.finishCompletion = completion
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate 
            
            self.speechSynthesizer.write(utterance) { [weak self] buffer in
                guard let self = self,
                      let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    print("⚠️ Invalid or nil buffer received")
                    return
                }
                
                // Validate buffer before using
                guard pcmBuffer.frameLength > 0,
                      pcmBuffer.format.channelCount > 0,
                      pcmBuffer.format.sampleRate > 0 else {
                    print("⚠️ Invalid buffer format: frames=\(pcmBuffer.frameLength)")
                    return
                }
                
                // Additional safety check
                guard audioPlayerNode.engine?.isRunning == true else {
                    print("⚠️ Audio engine not running")
                    return
                }
                
                // Store buffer reference to prevent deallocation
                self.bufferQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.currentBuffer = pcmBuffer
                    
                    // Schedule buffer on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Validate audio player node and engine again
                        guard audioPlayerNode.engine?.isRunning == true else {
                            print("⚠️ Audio engine not running - cannot schedule buffer")
                            self.bufferQueue.async {
                                self.currentBuffer = nil
                            }
                            return
                        }
                        
                        let playerFormat = audioPlayerNode.outputFormat(forBus: 0)
                        let bufferToSchedule: AVAudioPCMBuffer
                        
                        if pcmBuffer.format.channelCount != playerFormat.channelCount {
                            if let convertedBuffer = self.convertBuffer(pcmBuffer, toFormat: playerFormat) {
                                bufferToSchedule = convertedBuffer
                            } else {
                                print("❌ Failed to convert buffer to match player format")
                                self.bufferQueue.async {
                                    self.currentBuffer = nil
                                }
                                return
                            }
                        } else {
                            bufferToSchedule = pcmBuffer
                        }
                        
                        // Schedule buffer with completion handler
                        audioPlayerNode.scheduleBuffer(bufferToSchedule, completionHandler: nil)
                        
                        if !audioPlayerNode.isPlaying {
                            audioPlayerNode.play()
                        }
                        print("Audio buffer scheduled successfully")
                    }
                }
            }
        }
    }
    
    func stopAllSpeech(audioPlayerNode: AVAudioPlayerNode) {
        // Clear buffer reference to prevent memory issues
        bufferQueue.async { [weak self] in
            self?.currentBuffer = nil
        }
        
        // Stop TTS engine
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        // Stop and reset the player node
        audioPlayerNode.stop()
        audioPlayerNode.reset()
        
        // Clear completion handler
        finishCompletion = nil
        
        print("✅ All queued speech canceled, audio node reset, and buffers cleared.")
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer,
                               toFormat format: AVAudioFormat) -> AVAudioPCMBuffer? {
        
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            print("❌ Failed to create AVAudioConverter")
            return nil
        }
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity) else {
            print("❌ Failed to create converted PCM buffer")
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("❌ Error converting buffer: \(error)")
            return nil
        }
        
        return convertedBuffer
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        
        lastPlayedCircle = nil
        finishCompletion?()
        finishCompletion = nil
    }
}
