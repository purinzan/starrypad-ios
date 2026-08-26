import AVFoundation

/// A fixed pool of player nodes fed from preloaded buffers.
///
/// The desktop app gives SDL 96 mixer channels and picks a free one per hit;
/// this is the same shape in AVAudioEngine terms. Buffers are decoded once so a
/// hit never waits on file I/O, and the session asks for the shortest buffer
/// iOS will give, since the output path is where the latency lives on any
/// platform.
final class SamplePlayer {

    private let engine = AVAudioEngine()
    /// A gain stage the voices run through. AVAudioPlayerNode.volume and the
    /// main mixer both stop at 1.0, so making the app louder than "every voice
    /// flat out" needs somewhere that deals in decibels.
    /// Output gain in decibels, applied to the audio rather than to a node.
    ///
    /// Two attempts at an AVAudioUnitEQ in the chain gave a graph that either
    /// would not connect or would not accept the format, and an effect unit is
    /// a lot of machinery for one multiply. The desktop scales sample data for
    /// the same reason.
    private var makeup: Float = SamplePlayer.defaultMakeupDecibels
    private var voices: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    /// Trimmed and tuned versions, keyed by what made them. Deriving a buffer
    /// costs milliseconds, which is a whole hit's worth of latency, so it
    /// happens once and not on the way to the speaker.
    private var derived: [String: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private let format: AVAudioFormat

    init(voiceCount: Int = 24) {
        format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        configureSession(recording: false)
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
    }

    /// How much louder than unity the pads run by default.
    static let defaultMakeupDecibels: Float = 6

    /// Playback normally, playAndRecord only while the microphone is open.
    ///
    /// This is not a detail. iOS routes playAndRecord to the speakerphone and
    /// holds the level well below what playback gets, so leaving the session in
    /// playAndRecord all the time - which is what shipping the sampler first
    /// did - makes the whole instrument quiet even when nothing is recording.
    private func configureSession(recording: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if recording {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
        } catch {
            print("audio session category: \(error)")
        }
        // Preferences, not requirements. A device that will not hand over a
        // 3 ms buffer should still make sound; failing the whole setup over it
        // is how the session ends up inactive and the graph disconnected.
        try? session.setPreferredIOBufferDuration(0.003)
        try? session.setPreferredSampleRate(48000)
        do {
            try session.setActive(true)
        } catch {
            print("audio session activate: \(error)")
        }
    }

    /// Open the input route for the duration of a recording, then give it back.
    ///
    /// A category change can tear the engine down, so it is rebuilt after each
    /// one rather than assumed to have survived.
    func beginRecordingRoute() { restart(recording: true) }
    func endRecordingRoute() { restart(recording: false) }

    private func restart(recording: Bool) {
        engine.stop()
        configureSession(recording: recording)
        start()
    }

    /// Extra output gain in decibels, 0 to +12.
    var makeupDecibels: Float {
        get { makeup }
        set {
            let wanted = max(0, min(12, newValue))
            guard wanted != makeup else { return }
            makeup = wanted
            // Gain is baked into the derived buffers, so they are now stale.
            derived.removeAll()
        }
    }

    /// Decode every kit sample up front. Returns how many loaded.
    @discardableResult
    func preload(_ pads: [Pad]) -> Int {
        for pad in pads {
            let key = SoundSource.builtIn(file: pad.file).key
            guard buffers[key] == nil else { continue }
            guard let url = Self.bundleURL(for: pad.file),
                  let buffer = Self.buffer(at: url, as: format) else {
                print("missing sample: \(pad.file)")
                continue
            }
            buffers[key] = buffer
        }
        return buffers.count
    }

    /// Decode a recording made on the phone.
    @discardableResult
    func load(userSample name: String) -> Bool {
        let key = SoundSource.user(name: name).key
        if buffers[key] != nil { return true }
        guard let buffer = Self.buffer(at: Recordings.url(for: name), as: format) else { return false }
        buffers[key] = buffer
        return true
    }

    func start() {
        guard !engine.isRunning else { return }
        for voice in voices {
            engine.connect(voice, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("engine: \(error)")
            return
        }
        // Only start voices the engine actually owns: starting a node on a
        // graph that failed to wire up throws, and an uncaught throw here
        // takes the app down on launch.
        for voice in voices {
            voice.play()
        }
    }

    /// Play one hit. Velocity shapes gain through the ported curve; the slot
    /// contributes its own level, pan, tune and trim.
    func play(_ slot: PadSlot, velocity: Int) {
        guard let buffer = resolved(slot) else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = Velocity.gain(velocity) * Float(slot.level)
        voice.pan = Float(max(-1, min(1, slot.pan)))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Peaks for drawing, at whatever resolution the view asks for.
    func peaks(for source: SoundSource, bins: Int) -> [Float] {
        guard let buffer = buffers[source.key], let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0, bins > 0 else { return [] }
        let step = max(1, frames / bins)
        var out: [Float] = []
        out.reserveCapacity(bins)
        var index = 0
        while index < frames {
            var peak: Float = 0
            for frame in index..<min(index + step, frames) {
                peak = max(peak, abs(data[0][frame]))
            }
            out.append(peak)
            index += step
        }
        let loudest = out.max() ?? 1
        return loudest > 0 ? out.map { $0 / loudest } : out
    }

    func seconds(of source: SoundSource) -> Double {
        guard let buffer = buffers[source.key] else { return 0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    /// Drop derived buffers for a slot whose trim or tune has moved.
    func invalidate(_ source: SoundSource) {
        for key in derived.keys where key.hasPrefix(source.key) {
            derived.removeValue(forKey: key)
        }
    }

    // MARK: - Deriving

    private func resolved(_ slot: PadSlot) -> AVAudioPCMBuffer? {
        guard let original = buffers[slot.source.key] else { return nil }
        guard slot.isTrimmed || slot.tune != 0 || makeup > 0.01 else { return original }
        let key = "\(slot.source.key)|\(slot.start)|\(slot.end)|\(slot.tune)|\(makeup)"
        if let cached = derived[key] { return cached }
        var working = original
        if slot.isTrimmed, let cut = Self.trim(working, from: slot.start, to: slot.end) {
            working = cut
        }
        if slot.tune != 0, let tuned = Self.retune(working, semitones: slot.tune) {
            working = tuned
        }
        if makeup > 0.01, let louder = Self.amplify(working, decibels: makeup) {
            working = louder
        }
        derived[key] = working
        return working
    }

    private static func trim(_ buffer: AVAudioPCMBuffer, from start: Double, to end: Double)
        -> AVAudioPCMBuffer? {
        let total = Int(buffer.frameLength)
        let first = max(0, min(total - 1, Int(Double(total) * start)))
        let last = max(first + 1, min(total, Int(Double(total) * end)))
        let length = last - first
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                         frameCapacity: AVAudioFrameCount(length)),
              let source = buffer.floatChannelData, let target = out.floatChannelData
        else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel] + first, count: length)
        }
        out.frameLength = AVAudioFrameCount(length)
        return out
    }

    /// Multiply, then saturate rather than clip.
    ///
    /// tanh is close to a straight line until the signal approaches full scale
    /// and rounds off after that, so quiet material is untouched and a hard hit
    /// squashes instead of tearing. Hard clipping at +6 dB on a drum sounds
    /// like a fault; this sounds like a loud drum.
    private static func amplify(_ buffer: AVAudioPCMBuffer, decibels: Float) -> AVAudioPCMBuffer? {
        let gain = pow(10, decibels / 20)
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                         frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = out.floatChannelData
        else { return nil }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames {
                target[channel][frame] = tanh(source[channel][frame] * gain)
            }
        }
        out.frameLength = buffer.frameLength
        return out
    }

    /// Varispeed tuning: resample, so pitch and length move together, which is
    /// what tune means on a sampler and what the desktop does.
    private static func retune(_ buffer: AVAudioPCMBuffer, semitones: Int) -> AVAudioPCMBuffer? {
        let ratio = pow(2.0, Double(semitones) / 12.0)
        let total = Int(buffer.frameLength)
        let length = max(1, Int(Double(total) / ratio))
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                         frameCapacity: AVAudioFrameCount(length)),
              let source = buffer.floatChannelData, let target = out.floatChannelData
        else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<length {
                let position = Double(frame) * ratio
                let index = Int(position)
                guard index + 1 < total else {
                    target[channel][frame] = source[channel][min(index, total - 1)]
                    continue
                }
                let fraction = Float(position - Double(index))
                let a = source[channel][index], b = source[channel][index + 1]
                target[channel][frame] = a + (b - a) * fraction
            }
        }
        out.frameLength = AVAudioFrameCount(length)
        return out
    }

    /// Measured output latency, the number that actually matters to a player.
    var outputLatencyMilliseconds: Double {
        let session = AVAudioSession.sharedInstance()
        return (session.outputLatency + session.ioBufferDuration) * 1000.0
    }

    private static func bundleURL(for file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension
        return Bundle.main.url(forResource: name, withExtension: "wav")
    }

    private static func buffer(at url: URL, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: source)) != nil
        else { return nil }
        guard file.processingFormat != format else { return source }

        // Everything is converted to one format so the engine never resamples
        // mid hit; a phone recording arrives at whatever rate the hardware gave.
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let target = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(
                      Double(frames) * format.sampleRate / file.processingFormat.sampleRate) + 64
              )
        else { return source }
        var supplied = false
        var error: NSError?
        converter.convert(to: target, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? target : source
    }
}
