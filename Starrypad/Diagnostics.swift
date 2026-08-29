import AVFoundation
import Foundation
import UIKit

/// A short written record of what the app did, for attaching to a message.
///
/// Not analytics. Nothing here is sent anywhere by the app: it is written to
/// one file on the phone, it is shown to the person before it goes, and it
/// only ever travels as an attachment on a mail they wrote and sent
/// themselves. Which is also why it holds no content - no sample names, no
/// pad names, nothing typed - only the shape of what happened.
enum Diagnostics {

    /// Big enough for a session's worth of events, small enough to read.
    private static let maximumBytes = 120_000
    private static let queue = DispatchQueue(label: "starrypad.diagnostics")

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent("diagnostics.log")
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Record one line. Safe from any thread; the write happens off it.
    static func log(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let url = fileURL
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        trimIfLong(url)
    }

    /// Keep the tail. A log that grows without bound is a log nobody can
    /// send and a file nobody cleans up.
    private static func trimIfLong(_ url: URL) {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int, size > maximumBytes else {
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? ("…以前の記録は省略されました\n" + kept).write(to: url, atomically: true,
                                                encoding: .utf8)
    }

    // MARK: - Reading it back

    /// The whole thing, with what the device is at the top.
    static func report() -> String {
        let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "（記録はありません）"
        return header + "\n" + body
    }

    static var header: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let session = AVAudioSession.sharedInstance()
        return """
        Starrypad \(short) (\(build))
        \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(model)
        audio: \(Int(session.sampleRate)) Hz, buffer \
        \(String(format: "%.2f", session.ioBufferDuration * 1000)) ms, output \
        \(String(format: "%.2f", session.outputLatency * 1000)) ms
        """
    }

    private static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    /// The report as a file, for attaching.
    static func write() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("starrypad-log.txt")
        do {
            try report().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: - Launch and death

    private static let cleanKey = "diagnostics.closedCleanly"

    /// Called once at launch.
    ///
    /// The flag is how an unclean exit is noticed at all: iOS keeps the crash
    /// report to itself, but it cannot stop the app noticing that last time it
    /// never got to say goodbye.
    static func begin() {
        let defaults = UserDefaults.standard
        let closedCleanly = defaults.object(forKey: cleanKey) as? Bool ?? true
        defaults.set(false, forKey: cleanKey)

        log("---- 起動 ----")
        log(header.replacingOccurrences(of: "\n", with: " · "))
        if !closedCleanly {
            log("注意: 前回は正常に終了していません（クラッシュまたは強制終了）")
        }

        // Everything here is named through the type, because a handler that
        // becomes a C function pointer may capture nothing at all - not even
        // an implicit Self.
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.recordFatal(exception)
        }
    }

    /// Last words, written in place.
    ///
    /// The queue is asynchronous and this thread is about to stop existing,
    /// so this one write does not go through it.
    static func recordFatal(_ exception: NSException) {
        let line = "致命的: \(exception.name.rawValue) — "
            + "\(exception.reason ?? "理由なし")\n"
            + exception.callStackSymbols.prefix(12).joined(separator: "\n") + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = Diagnostics.fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Called when the app goes to the background, which is the last moment
    /// anyone can be sure of.
    static func end() {
        log("---- 背面へ ----")
        UserDefaults.standard.set(true, forKey: cleanKey)
    }
}
