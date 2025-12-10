
//
//  SpatialAnnouncer.swift
//  SSDMobileNet
//
//  Provides spoken feedback with basic left/center/right spatialization.
//  Uses AVAudioEngine + AVAudioEnvironmentNode when available;
//  falls back to AVSpeechSynthesizer.speak otherwise.
//

import Foundation
import AVFoundation

public final class SpatialAnnouncer: NSObject {

    public struct Utterance {
        public let text: String
        /// x position of the object in view space normalized [0,1] (0 = left, 1 = right).
        public let xNormalized: CGFloat
        /// Estimated distance in meters (affects spatial position); optional.
        public let distanceM: Float?

        public init(text: String, xNormalized: CGFloat, distanceM: Float?) {
            self.text = text
            self.xNormalized = xNormalized
            self.distanceM = distanceM
        }
    }

    private let speech = AVSpeechSynthesizer()

    // Spatial pipeline
    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()

    private var useSpatial = false
    private var isEngineRunning = false

    // Throttling
    private var lastSpokenAt = Date.distantPast
    public var minInterval: TimeInterval = 1.25

    public override init() {
        super.init()
        speech.delegate = self
        configureAudio()
    }

    private func configureAudio() {
        // Try to set up an environment for spatial audio.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            NSLog("AudioSession error: \(error.localizedDescription)")
        }

        // No renderingMode on AVAudioEnvironmentNode in iOS; it auto-selects output mode.
        engine.attach(env)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        engine.prepare()

        do {
            try engine.start()
            isEngineRunning = true
            useSpatial = true
        } catch {
            NSLog("Failed to start AVAudioEngine, falling back to plain TTS: \(error.localizedDescription)")
            useSpatial = false
            isEngineRunning = false
        }
    }

    public func speak(_ u: Utterance) {
        // Rate limit
        let now = Date()
        guard now.timeIntervalSince(lastSpokenAt) >= minInterval else { return }
        lastSpokenAt = now

        if useSpatial {
            speakSpatial(u)
        } else {
            speakPlain(u.text)
        }
    }

    private func speakPlain(_ text: String) {
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utt)
    }

    private func speakSpatial(_ u: Utterance) {
        // Generate buffers from Speech and play them at a position in the environment.
        let utterance = AVSpeechUtterance(string: u.text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        // Player per utterance
        let player = AVAudioPlayerNode()
        player.renderingAlgorithm = .HRTFHQ
        engine.attach(player)

        // Connect with no explicit format to let the engine handle conversion.
        engine.connect(player, to: env, format: nil)

        // Place sound in front at ±55° depending on xNormalized
        let azimuthRad = (-.pi/5) + (2 * .pi/5) * Float(u.xNormalized)  // ~ -36° ... +36°
        let r: Float = max(0.4, min(2.0, (u.distanceM ?? 1.0)))          // distance clamp for audibility
        let x = r * sinf(azimuthRad)
        let z = -r * cosf(azimuthRad)
        player.position = AVAudio3DPoint(x: x, y: 0, z: z)

        // Schedule buffers from AVSpeechSynthesizer
        var buffers: [AVAudioPCMBuffer] = []

        speech.write(utterance) { buf in
            if let pcm = buf as? AVAudioPCMBuffer {
                buffers.append(pcm)
            }
        }

        // Schedule asynchronously after generation; quick micro-delay to ensure buffers are collected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self else { return }
            guard !buffers.isEmpty else { self.speakPlain(u.text); return }

            for (idx, b) in buffers.enumerated() {
                let options: AVAudioPlayerNodeBufferOptions = (idx == buffers.count - 1) ? [.interruptsAtLoop] : []
                player.scheduleBuffer(b, completionCallbackType: .dataConsumed) { _ in }
            }
            if !self.engine.isRunning {
                do { try self.engine.start() } catch { NSLog("Engine start failed: \(error)"); self.speakPlain(u.text) }
            }
            player.play()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpatialAnnouncer: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // no-op
    }
}
