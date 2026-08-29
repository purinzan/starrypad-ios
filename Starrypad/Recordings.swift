import AVFoundation
import Foundation
import OSLog

/// Where recordings live, and what they are called.
///
/// One flat folder in Documents, names stamped with the time they were made.
/// Nothing overwrites anything: a slot points at a name, and undoing an
/// assignment has to find the old sound still there.
enum Recordings {
    private static let log = Logger(subsystem: "com.purinzan.starrypad", category: "Recording")

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func newName(prefix: String) -> String {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(prefix)-\(stamp).wav"
    }

    /// The region of a recording that plays.
    ///
    /// It belongs to the recording, not to the pad. Trimming a sample and then
    /// putting it on another pad - or the same pad again from the picker -
    /// should not throw the trim away; the part you chose is part of what the
    /// sample now is.
    static func trim(for name: String) -> (start: Double, end: Double) {
        guard let raw = UserDefaults.standard.dictionary(forKey: trimsKey) as? [String: [Double]],
              let pair = raw[name], pair.count == 2,
              pair[0] >= 0, pair[1] <= 1, pair[1] > pair[0]
        else { return (0, 1) }
        return (pair[0], pair[1])
    }

    static func setTrim(start: Double, end: Double, for name: String) {
        var raw = (UserDefaults.standard.dictionary(forKey: trimsKey) as? [String: [Double]]) ?? [:]
        raw[name] = [start, end]
        UserDefaults.standard.set(raw, forKey: trimsKey)
    }

    static func forget(_ name: String) {
        var raw = (UserDefaults.standard.dictionary(forKey: trimsKey) as? [String: [Double]]) ?? [:]
        raw.removeValue(forKey: name)
        UserDefaults.standard.set(raw, forKey: trimsKey)
        var labels = (UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String]) ?? [:]
        labels.removeValue(forKey: name)
        UserDefaults.standard.set(labels, forKey: labelsKey)
    }

    /// A name someone gave a recording, which travels with it the way its
    /// region does.
    static func label(for name: String) -> String? {
        let raw = UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String]
        return raw?[name]
    }

    static func setLabel(_ label: String, for name: String) {
        var raw = (UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String]) ?? [:]
        raw[name] = label
        UserDefaults.standard.set(raw, forKey: labelsKey)
    }

    private static let trimsKey = "recordings.trims"
    private static let labelsKey = "recordings.labels"

    static func all() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".wav") }.sorted()
    }
}

/// Records the microphone straight to a wav.
///
/// AVAudioRecorder rather than a tap on the engine: the engine is already
/// running for playback, and asking it to also own the input graph is how you
/// get a route change to take the pads down with it.
final class Recorder: NSObject, ObservableObject {
    /// The longest a single take may run, in seconds.
    ///
    /// The same thirty the video import takes, for the same two reasons: a
    /// sampler wants a sound and not a performance, and a loaded buffer is
    /// eleven megabytes a minute per pad whether or not anyone plays it.
    static let longestRecording: TimeInterval = 30

    /// Called when the take ended by itself rather than by being stopped, so
    /// the screen that started it can finish the job. Without this the ceiling
    /// would stop the recorder and leave the app still saying "recording".
    var onEndedItself: ((String?) -> Void)?

    private static let log = Logger(subsystem: "com.purinzan.starrypad", category: "Recording")


    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0       // 0...1, for the meter
    @Published private(set) var seconds: Double = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentName: String?

    /// Ask once. iOS shows its own prompt; refusing is a normal answer.
    func requestAccess(_ done: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { done(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { done(granted) }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isRecording else { return false }
        let name = Recordings.newName(prefix: "mic")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: Recordings.url(for: name), settings: settings)
            recorder.isMeteringEnabled = true
            // A ceiling, because nothing else stops this. Forgetting the app
            // is recording should cost you a minute of disk, not the rest of
            // the phone's storage and a buffer too large to hold - and the
            // sampler takes the first thirty seconds of it anyway.
            guard recorder.record(forDuration: Self.longestRecording) else { return false }
            self.recorder = recorder
            currentName = name
            isRecording = true
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.sampleMeter()
            }
            return true
        } catch {
            Self.log.error("recorder: \(error.localizedDescription)")
            Diagnostics.log("録音を開始できません: \(error.localizedDescription)")
            return false
        }
    }

    /// Stop and hand back the name, or nil if nothing usable was captured.
    func stop() -> String? {
        guard let recorder, isRecording else { return nil }
        recorder.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        level = 0
        self.recorder = nil
        guard let name = currentName else { return nil }
        currentName = nil
        // A tap that lasts a few frames is a mis-hit, not a sample.
        guard seconds > 0.05 else {
            try? FileManager.default.removeItem(at: Recordings.url(for: name))
            return nil
        }
        return name
    }

    private func sampleMeter() {
        guard let recorder else { return }
        // It stops itself at the ceiling. The model has to notice, or the
        // meter freezes and the button goes on claiming to be recording.
        guard recorder.isRecording else {
            let name = stop()
            onEndedItself?(name)
            return
        }
        recorder.updateMeters()
        // dBFS is logarithmic and mostly empty at the bottom; -50 dB is a
        // usable floor for a meter someone is watching while they play.
        let decibels = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (decibels + 50) / 50))
        seconds = recorder.currentTime
    }
}
