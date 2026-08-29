import AVFoundation
import OSLog

/// A fixed pool of player nodes fed from preloaded buffers.
///
/// The desktop app gives SDL 96 mixer channels and picks a free one per hit;
/// this is the same shape in AVAudioEngine terms. Buffers are decoded once so a
/// hit never waits on file I/O, and the session asks for the shortest buffer
/// iOS will give, since the output path is where the latency lives on any
/// platform.
final class SamplePlayer {
    private static let log = Logger(subsystem: "com.purinzan.starrypad", category: "Audio")

    private let engine = AVAudioEngine()

    /// The master gain, as a node rather than as arithmetic on the samples.
    ///
    /// It used to be baked into the buffers, which meant turning the knob
    /// rebuilt every sample in the kit and you heard the change on the next
    /// hit rather than on this one. A knob that answers late is a knob you
    /// cannot set by ear. AVAudioPlayerNode.volume and the main mixer both
    /// stop at 1.0, so the stage that deals in decibels is an EQ with no
    /// bands - all it is here for is its global gain.
    private let gain = AVAudioUnitEQ(numberOfBands: 0)

    /// The voices meet here first. An effect node has one input bus, so
    /// connecting twenty-four players straight to the gain stage left the
    /// twenty-fourth connected and the rest silently unplugged - which the
    /// engine reports, eventually, as "player started when in a disconnected
    /// state". Mixers are the nodes that take many inputs; effects are not.
    private let submix = AVAudioMixerNode()

    /// And behind it, a limiter, because the soft clip that used to be applied
    /// with the gain went with it. Boosting into a bare output tears; boosting
    /// into this squashes, which is what a loud drum does anyway.
    private let limiter: AVAudioUnitEffect = {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = kAudioUnitSubType_PeakLimiter
        description.componentManufacturer = kAudioUnitManufacturer_Apple
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

    private var makeup: Float = SamplePlayer.defaultMakeupDecibels
    private var voices: [AVAudioPlayerNode] = []
    /// How many of them the pads may use. The rest are reserved.
    private var playable = 1
    /// Peaks are a scan of the whole file, and the trim view asks for them on
    /// every frame of a drag. Scanning a thirty second import sixty times a
    /// second is the difference between a smooth drag and a stuttering one.
    private var peakCache: [String: [Float]] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    /// Trimmed and tuned versions, keyed by what made them. Deriving a buffer
    /// costs milliseconds, which is a whole hit's worth of latency, so it
    /// happens once and not on the way to the speaker.
    private var derived: [String: AVAudioPCMBuffer] = [:]
    /// Which sound each voice last took, parallel to voices. A sample that is
    /// already sounding is retriggered on the voice it is already on.
    private var voiceSources: [String?] = []
    /// Whether each voice still has something sounding on it, and when it was
    /// last started. A round robin hands out voices whether or not they are
    /// free, which is how a long sample got cut off by the twenty-third hit
    /// after it - hits that had nothing to do with it and no reason to stop
    /// it. Idle voices are handed out first, and only when every one of them
    /// is genuinely sounding does the oldest get taken.
    private var voiceBusy: [Bool] = []
    private var voiceStamp: [Int] = []
    private var clock = 0
    /// What each voice is currently sounding, for choking. Parallel to voices.
    private var voiceGroups: [String?] = []
    private let format: AVAudioFormat
    private var recordingRoute = false

    init(voiceCount: Int = 24) {
        format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        configureSession(recording: false)
        engine.attach(submix)
        engine.attach(gain)
        engine.attach(limiter)
        engine.connect(submix, to: gain, format: format)
        engine.connect(gain, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        gain.globalGain = makeup
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: submix, format: format)
            voices.append(node)
        }
        voiceGroups = Array(repeating: nil, count: voices.count)
        voiceSources = Array(repeating: nil, count: voices.count)
        voiceBusy = Array(repeating: false, count: voices.count)
        voiceStamp = Array(repeating: 0, count: voices.count)
        // The last voice is not in the round robin. Auditions land on it and
        // nowhere else, so listening to a trim four times in a row is four
        // sounds one after another rather than four at once.
        playable = max(1, voices.count - 1)
        observeInterruptions()
    }

    /// Come back from the things that take the audio away.
    ///
    /// The background audio mode and a playback session are what let this keep
    /// sounding behind another app, but neither survives a phone call on its
    /// own: an interruption stops the engine, and without this nothing ever
    /// starts it again, so the app is silent from then on - including once it
    /// is back in front. Media services resetting is rarer and worse, since the
    /// session itself has to be rebuilt.
    private func observeInterruptions() {
        let centre = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        centre.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: session, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.engine.pause()
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                // iOS says whether it expects us back; asking anyway is how you
                // end up fighting whatever interrupted you.
                guard options.contains(.shouldResume) else { return }
                self.configureSession(recording: self.recordingRoute, reason: "interruption ended")
                self.engine.stop()
                self.start()
            @unknown default:
                break
            }
        }

        centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.engine.stop()
            self.configureSession(recording: self.recordingRoute, reason: "media services reset")
            self.start()
        }

        centre.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: session, queue: .main) { [weak self] _ in
            // Headphones in or out rebuilds the output chain underneath us.
            guard let self else { return }
            self.activateSession(reason: "route changed")
            guard !self.engine.isRunning else { return }
            self.start()
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
    private func configureSession(recording: Bool, reason: String = "configure") {
        let session = AVAudioSession.sharedInstance()
        recordingRoute = recording
        do {
            if recording {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
        } catch {
            Self.log.error("audio session category (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
        // Preferences, not requirements. A device that will not hand over a
        // 3 ms buffer should still make sound; failing the whole setup over it
        // is how the session ends up inactive and the graph disconnected.
        try? session.setPreferredIOBufferDuration(0.003)
        try? session.setPreferredSampleRate(48000)
        do {
            try session.setActive(true)
            Self.log.info("audio session active: \(recording ? "playAndRecord" : "playback", privacy: .public) (\(reason, privacy: .public))")
        } catch {
            Self.log.error("audio session activate (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reclaim the foreground audio session without rebuilding the engine when
    /// it is already healthy. This is the app-level "audio leadership" path:
    /// exclusive session activation, not user volume control.
    func activateSession(reason: String = "foreground") {
        configureSession(recording: recordingRoute, reason: reason)
        if !engine.isRunning {
            start()
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

    /// How far the master knob goes, in decibels either side of unity.
    static let makeupRange: ClosedRange<Float> = -24...24

    /// Master gain in decibels. Takes effect on the sound already in the air,
    /// because it is a parameter on a running node and not a property of the
    /// samples.
    var makeupDecibels: Float {
        get { makeup }
        set {
            let wanted = max(Self.makeupRange.lowerBound,
                             min(Self.makeupRange.upperBound, newValue))
            guard wanted != makeup else { return }
            makeup = wanted
            gain.globalGain = wanted
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
                Self.log.error("missing sample: \(pad.file)")
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
        engine.connect(submix, to: gain, format: format)
        engine.connect(gain, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        for voice in voices {
            engine.connect(voice, to: submix, format: format)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // The session can be briefly unavailable at launch - a call ending,
            // another audio app letting go. Failing once and staying silent for
            // the rest of the session is the worst possible answer, so it tries
            // again shortly rather than giving up.
            Self.log.error("engine start: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.engine.isRunning else { return }
                self.configureSession(recording: false)
                do {
                    try self.engine.start()
                } catch {
                    Self.log.error("engine retry: \(error.localizedDescription, privacy: .public)")
                    return
                }
                for voice in self.voices { voice.play() }
            }
            return
        }
        // Only start voices the engine actually owns: starting a node on a
        // graph that failed to wire up throws, and an uncaught throw here
        // takes the app down on launch.
        for voice in voices {
            voice.play()
        }
        let session = AVAudioSession.sharedInstance()
        Self.log.info("audio: buffer \(session.ioBufferDuration * 1000, format: .fixed(precision: 2)) ms (asked 3.00), output \(session.outputLatency * 1000, format: .fixed(precision: 2)) ms, rate \(session.sampleRate, format: .fixed(precision: 0)) Hz")
    }

    /// Play one hit. Velocity shapes gain through the ported curve; the slot
    /// contributes its own level, pan, tune and trim.
    func play(_ slot: PadSlot, velocity: Int) {
        guard let buffer = resolved(slot) else { return }
        if let group = slot.chokeGroup { choke(group) }
        // A sample cuts itself off and nothing else. Hit the same pad twice
        // and the second hit lands on the voice the first is still using, so
        // .interrupts replaces it - one copy of a sample, however fast you
        // play it. Two different samples never touch each other, and a kit
        // piece is left to ring the way a drum does.
        let index: Int
        if slot.source.isUser,
           let sounding = voiceSources.firstIndex(of: slot.source.key),
           sounding < playable, voiceBusy[sounding] {
            index = sounding
        } else if let crowded = overLimit(slot) {
            index = crowded
        } else {
            index = freeVoice()
        }
        voiceGroups[index] = slot.chokeGroup
        voiceSources[index] = slot.source.key
        let voice = voices[index]
        voice.volume = Velocity.gain(velocity) * Float(slot.level)
        voice.pan = Float(max(-1, min(1, slot.pan)))
        schedule(buffer, on: index)
    }

    /// The voice a pad at its limit should take over, if it is at its limit.
    ///
    /// Counting what is already sounding of this exact sound: at the limit,
    /// the oldest of them gives way, so a crash hit again is one cymbal being
    /// struck again rather than a second cymbal appearing beside it.
    private func overLimit(_ slot: PadSlot) -> Int? {
        guard let limit = slot.voiceLimit, limit > 0 else { return nil }
        let sounding = (0..<playable).filter {
            voiceBusy[$0] && voiceSources[$0] == slot.source.key
        }
        guard sounding.count >= limit else { return nil }
        return sounding.min { voiceStamp[$0] < voiceStamp[$1] }
    }

    /// An idle voice if there is one, otherwise the one sounding longest.
    private func freeVoice() -> Int {
        var oldest = 0
        for index in 0..<playable {
            if !voiceBusy[index] { return index }
            if voiceStamp[index] < voiceStamp[oldest] { oldest = index }
        }
        return oldest
    }

    /// Hand a buffer to a voice and remember that it is busy until it is not.
    ///
    /// The stamp is what makes the completion trustworthy: interrupting a
    /// buffer calls its handler too, and without something to compare against,
    /// the voice that had just been given new work would be marked idle.
    private func schedule(_ buffer: AVAudioPCMBuffer, on index: Int) {
        clock += 1
        let generation = clock
        voiceStamp[index] = generation
        voiceBusy[index] = true
        voices[index].scheduleBuffer(buffer, at: nil, options: .interrupts,
                                     completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.voiceStamp[index] == generation else { return }
                self.voiceBusy[index] = false
                self.voiceSources[index] = nil
            }
        }
    }

    /// Hear a sound without playing it: one at a time, replacing the last.
    ///
    /// A preview is not a hit. Hits are meant to pile up - that is what a
    /// drum kit is - but pressing Hear twice, or dragging a trim twice, is
    /// one person asking one question twice, and answering it twice over the
    /// top of itself makes the answer harder to hear, not easier. The reserved
    /// voice takes the new buffer with .interrupts, which cuts the old one.
    func audition(_ slot: PadSlot, velocity: Int) {
        guard let voice = voices.last, let buffer = resolved(slot) else { return }
        voice.volume = Velocity.gain(velocity) * Float(slot.level)
        voice.pan = Float(max(-1, min(1, slot.pan)))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Silence whatever is still ringing in this group.
    ///
    /// Stopping the node rather than fading it: a sampler's choke is a cut,
    /// and the hit doing the choking covers it - a closed hat lands on top of
    /// the open one it is silencing.
    private func choke(_ group: String) {
        for index in voices.indices where voiceGroups[index] == group {
            voices[index].stop()
            voices[index].play()
            voiceGroups[index] = nil
            voiceSources[index] = nil
            voiceBusy[index] = false
        }
    }

    /// A count-in click, made rather than sampled.
    ///
    /// Two short pings, the first beat of the bar higher than the rest, so you
    /// can hear where the bar starts without watching anything. Synthesised
    /// because a click is a sine and a decay, and shipping a wav for that would
    /// be a file to carry and a licence to explain.
    func click(accent: Bool) {
        let key = accent ? "click:accent" : "click:beat"
        if buffers[key] == nil {
            buffers[key] = Self.clickBuffer(hertz: accent ? 1600 : 1000, as: format)
        }
        guard let buffer = buffers[key] else { return }
        // The click takes an idle voice like anything else. Walking a pointer
        // through the pool meant a metronome running under a take chewed
        // through every voice in the rack four times a bar.
        let index = freeVoice()
        voiceGroups[index] = nil
        voiceSources[index] = nil
        voices[index].volume = 0.55
        voices[index].pan = 0
        schedule(buffer, on: index)
    }

    private static func clickBuffer(hertz: Double, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds = 0.035
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData else { return nil }
        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            // Steep decay: a click that rings is a tone, and a tone in a count
            // in is something you play along with by mistake.
            let value = Float(sin(2 * .pi * hertz * t) * exp(-t * 90))
            for channel in 0..<Int(format.channelCount) { data[channel][frame] = value }
        }
        buffer.frameLength = frames
        return buffer
    }

    /// Peaks for drawing, at whatever resolution the view asks for.
    func peaks(for source: SoundSource, bins: Int) -> [Float] {
        let cacheKey = "\(source.key)#\(bins)"
        if let cached = peakCache[cacheKey] { return cached }
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
        let normalised = loudest > 0 ? out.map { $0 / loudest } : out
        peakCache[cacheKey] = normalised
        return normalised
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
        // Trim and tune do not change the shape of the file, but a reassigned
        // pad does, and the cheap thing is to drop them either way.
        for key in peakCache.keys where key.hasPrefix(source.key) {
            peakCache.removeValue(forKey: key)
        }
    }

    // MARK: - Deriving

    /// Gain is already in the base buffer, so an untrimmed, untuned pad - the
    /// common case, and every pad on a fresh kit - does no work at all here.
    private func resolved(_ slot: PadSlot) -> AVAudioPCMBuffer? {
        guard let base = buffers[slot.source.key] else { return nil }
        guard slot.isTrimmed || slot.tune != 0 else { return base }
        let key = "\(slot.source.key)|\(slot.start)|\(slot.end)|\(slot.tune)"
        if let cached = derived[key] { return cached }
        var working = base
        if slot.isTrimmed, let cut = Self.trim(working, from: slot.start, to: slot.end) {
            working = cut
        }
        if slot.tune != 0, let tuned = Self.retune(working, semitones: slot.tune) {
            working = tuned
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
