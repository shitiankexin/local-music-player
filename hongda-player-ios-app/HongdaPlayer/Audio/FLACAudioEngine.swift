import Foundation
import AVFAudio

/// All decoder and AVAudioEngine mutations happen on a dedicated serial queue.
/// UI observes only callbacks dispatched onto the main queue.
final class FLACAudioEngine {
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onOutputSampleRate: ((Double) -> Void)?
    var onPlaybackInterrupted: ((TimeInterval) -> Void)?
    var onPlaybackResumed: (() -> Void)?

    private let queue = DispatchQueue(label: "hongdakuaibo.audio", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    // The graph is attached once. Realtime on/off uses bypass instead of
    // tearing down the graph (which would interrupt playback/lyrics timing).
    private let equalizer = AVAudioUnitEQ(numberOfBands: 12)
    private let reverb = AVAudioUnitReverb()
    private var effects = AudioEffectsSettings()
    private var appliedReverbSpace: AudioReverbSpace?
    private var decoder: FLACDecoder?
    private var sampleRate: Double = 44_100
    private var baseSample: Int64 = 0
    // Exact sample captured after pause. Never advance the UI while paused.
    private var frozenSample: Int64?
    private var totalSamples: UInt64 = 0
    private var inFlight = 0
    private var reachedEnd = false
    private var desiredPlaying = false
    private var wasPlayingBeforeInterruption = false
    private var generation = 0
    private let maxScheduledBuffers = 16
    private var observers: [NSObjectProtocol] = []

    init() {
        engine.attach(node)
        engine.attach(equalizer)
        engine.attach(reverb)
        for index in AudioEffectsSettings.frequencies.indices {
            let band = equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = AudioEffectsSettings.frequencies[index]
            band.bandwidth = 1.0
            band.gain = 0
        }
        let bassShelf = equalizer.bands[10]
        bassShelf.filterType = .lowShelf
        bassShelf.frequency = 100
        bassShelf.gain = 0
        let trebleShelf = equalizer.bands[11]
        trebleShelf.filterType = .highShelf
        trebleShelf.frequency = 8_000
        trebleShelf.gain = 0
        applyEffectsOnAudioQueue(effects)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                                        object: nil, queue: nil) { [weak self] note in
            guard let self else { return }
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            self.queue.async {
                // Avoid unexpectedly blasting music through the speaker if the
                // Bluetooth / wired headphones disconnect during playback.
                if reason == .oldDeviceUnavailable && self.desiredPlaying {
                    self.desiredPlaying = false
                    self.wasPlayingBeforeInterruption = false
                    let beforePause = self.currentSample()
                    self.node.pause()
                    let sample = max(beforePause, self.currentSampleIgnoringFreeze())
                    self.frozenSample = sample
                    let seconds = Double(sample) / self.sampleRate
                    DispatchQueue.main.async {
                        self.onPlaybackInterrupted?(seconds)
                    }
                }
                self.rebuildAfterRouteChange()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self.queue.async {
                switch type {
                case .began:
                    self.wasPlayingBeforeInterruption = self.desiredPlaying
                    self.desiredPlaying = false
                    let beforePause = self.currentSample()
                    self.node.pause()
                    let sample = max(beforePause, self.currentSampleIgnoringFreeze())
                    self.frozenSample = sample
                    let seconds = Double(sample) / self.sampleRate
                    DispatchQueue.main.async {
                        self.onPlaybackInterrupted?(seconds)
                    }
                case .ended:
                    let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let canResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                        .contains(.shouldResume)
                    let shouldAutoResume = canResume && self.wasPlayingBeforeInterruption
                    self.wasPlayingBeforeInterruption = false
                    if shouldAutoResume {
                        do {
                            try AVAudioSession.sharedInstance().setActive(true)
                            if !self.engine.isRunning { try self.engine.start() }
                            self.desiredPlaying = true
                            self.frozenSample = nil
                            self.node.play()
                            DispatchQueue.main.async { self.onPlaybackResumed?() }
                        } catch {
                            self.reportFailure("音频会话恢复失败：\(error.localizedDescription)")
                        }
                    }
                @unknown default: break
                }
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func open(url: URL, playAutomatically: Bool = true) {
        queue.async {
            do {
                self.generation += 1
                self.node.stop()
                self.engine.stop()
                self.decoder = nil
                self.inFlight = 0
                self.reachedEnd = false
                self.baseSample = 0
                self.frozenSample = nil
                self.desiredPlaying = playAutomatically
                self.wasPlayingBeforeInterruption = false

                let decoder = try FLACDecoder(url: url)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default, options: [])
                try? audioSession.setPreferredSampleRate(decoder.format.sampleRate)
                try audioSession.setActive(true)

                self.decoder = decoder
                self.sampleRate = decoder.format.sampleRate
                self.totalSamples = decoder.details.totalSamples
                self.connectEffectsGraph(format: decoder.format)
                self.node.volume = 1.0
                self.engine.mainMixerNode.outputVolume = 1.0
                try self.engine.start()
                self.fillBuffers()
                if playAutomatically { self.node.play() }
                let outputRate = audioSession.sampleRate
                DispatchQueue.main.async { self.onOutputSampleRate?(outputRate) }
            } catch {
                self.reportFailure("无法开始播放：\(error.localizedDescription)")
            }
        }
    }

    /// Apply settings while playback runs. Called only through the audio queue,
    /// never from a render or AVAudioPlayerNode completion callback.
    func updateEffects(_ requested: AudioEffectsSettings) {
        queue.async {
            self.effects = requested.sanitized()
            self.applyEffectsOnAudioQueue(self.effects)
        }
    }

    private func connectEffectsGraph(format: AVAudioFormat) {
        engine.connect(node, to: equalizer, format: format)
        engine.connect(equalizer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    private func applyEffectsOnAudioQueue(_ settings: AudioEffectsSettings) {
        // Complete bypass by default. Neither the file nor decoder is modified.
        for index in AudioEffectsSettings.frequencies.indices {
            equalizer.bands[index].gain = settings.bands[index]
        }
        equalizer.bands[10].gain = settings.bassDB
        equalizer.bands[11].gain = settings.trebleDB
        equalizer.globalGain = settings.enabled ? settings.effectivePreampDB : 0
        // Loading a factory preset repeatedly during slider drags could
        // glitch the audio. Reload only when the selected room changes.
        if appliedReverbSpace != settings.reverbSpace {
            switch settings.reverbSpace {
            case .smallRoom: reverb.loadFactoryPreset(.smallRoom)
            case .mediumRoom: reverb.loadFactoryPreset(.mediumRoom)
            case .mediumHall: reverb.loadFactoryPreset(.mediumHall)
            case .largeHall: reverb.loadFactoryPreset(.largeHall)
            }
            appliedReverbSpace = settings.reverbSpace
        }
        reverb.wetDryMix = settings.enabled && settings.reverbEnabled
            ? settings.reverbMix : 0
        node.pan = settings.enabled ? settings.balance : 0
        equalizer.bypass = !settings.enabled
        reverb.bypass = !(settings.enabled && settings.reverbEnabled)
    }

    func resume() {
        queue.async {
            guard self.decoder != nil else { return }
            self.desiredPlaying = true
            self.frozenSample = nil
            self.wasPlayingBeforeInterruption = false
            if !self.engine.isRunning { try? self.engine.start() }
            self.node.play()
        }
    }

    /// Capture actual playback position on the audio queue, AFTER pausing the node.
    /// The completion runs on the main queue; headset and on-screen pause share it.
    func pause(completion: @escaping (TimeInterval) -> Void) {
        queue.async {
            self.desiredPlaying = false
            self.wasPlayingBeforeInterruption = false
            let beforePause = self.currentSample()
            self.node.pause()
            let sample = max(beforePause, self.currentSampleIgnoringFreeze())
            self.frozenSample = sample
            let seconds = Double(sample) / self.sampleRate
            DispatchQueue.main.async { completion(seconds) }
        }
    }

    func stop() {
        queue.async {
            self.generation += 1
            self.desiredPlaying = false
            self.wasPlayingBeforeInterruption = false
            self.node.stop()
            self.engine.stop()
            self.decoder = nil
            self.inFlight = 0
            self.reachedEnd = true
            self.baseSample = 0
            self.frozenSample = nil
        }
    }

    func seek(seconds: TimeInterval) {
        queue.async {
            guard let decoder = self.decoder else { return }
            let maxSeconds = self.totalSamples == 0 ? seconds :
                Double(self.totalSamples) / self.sampleRate
            let targetSeconds = min(max(0, seconds), maxSeconds)
            /* Keep end-seeks inside the last sample for libFLAC. */
            let sample = self.totalSamples == 0
                ? UInt64(targetSeconds * self.sampleRate)
                : min(UInt64(targetSeconds * self.sampleRate), self.totalSamples - 1)
            do {
                self.generation += 1
                self.node.stop()   // clears queued buffers and its player timeline
                self.inFlight = 0
                self.reachedEnd = false
                try decoder.seek(sample: sample)
                self.baseSample = Int64(sample)
                self.frozenSample = self.desiredPlaying ? nil : Int64(sample)
                self.fillBuffers()
                if self.desiredPlaying { self.node.play() }
            } catch {
                self.reportFailure("跳转失败：\(error.localizedDescription)")
            }
        }
    }

    func currentPosition(_ reply: @escaping (TimeInterval) -> Void) {
        queue.async {
            let seconds = Double(self.currentSample()) / self.sampleRate
            DispatchQueue.main.async { reply(seconds) }
        }
    }

    private func currentSample() -> Int64 {
        frozenSample ?? currentSampleIgnoringFreeze()
    }

    private func currentSampleIgnoringFreeze() -> Int64 {
        var renderedFrames: Int64 = 0
        if let lastTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: lastTime) {
            renderedFrames = max(0, playerTime.sampleTime)
        }
        let sample = baseSample + renderedFrames
        return totalSamples > 0 ? min(sample, Int64(totalSamples)) : sample
    }

    private func fillBuffers() {
        guard let decoder else { return }
        while inFlight < maxScheduledBuffers && !reachedEnd {
            do {
                guard let pcm = try decoder.readBuffer() else {
                    reachedEnd = true
                    break
                }
                let token = generation
                inFlight += 1
                /* Callback is not a safe place to block or stop the player. */
                node.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async {
                        guard token == self.generation else { return }
                        self.inFlight -= 1
                        self.fillBuffers()
                        if self.reachedEnd && self.inFlight == 0 && self.desiredPlaying {
                            self.desiredPlaying = false
                            DispatchQueue.main.async { self.onFinished?() }
                        }
                    }
                }
            } catch {
                reachedEnd = true
                reportFailure(error.localizedDescription)
            }
        }
    }

    private func rebuildAfterRouteChange() {
        guard let decoder else { return }
        let previousSample = currentSample()
        generation += 1
        node.stop()
        engine.stop()
        inFlight = 0
        reachedEnd = false
        do {
            let target = totalSamples > 0
                ? min(UInt64(max(0, previousSample)), totalSamples - 1)
                : UInt64(max(0, previousSample))
            try decoder.seek(sample: target)
            baseSample = Int64(target)
            frozenSample = desiredPlaying ? nil : Int64(target)
            connectEffectsGraph(format: decoder.format)
            try engine.start()
            fillBuffers()
            if desiredPlaying { node.play() }
            let rate = AVAudioSession.sharedInstance().sampleRate
            DispatchQueue.main.async { self.onOutputSampleRate?(rate) }
        } catch {
            reportFailure("音频输出设备切换失败：\(error.localizedDescription)")
        }
    }

    private func reportFailure(_ message: String) {
        desiredPlaying = false
        wasPlayingBeforeInterruption = false
        DispatchQueue.main.async { self.onFailure?(message) }
    }
}
