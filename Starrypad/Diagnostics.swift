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

    /// What the app is actually using, which is the number that matters when
    /// something disappears without a word.
    static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// A line of vital signs, for the moments worth marking.
    static func vitals(_ occasion: String, events: Int) {
        log(String(format: "%@: %d 打 · メモリ %.0f MB", occasion, events, footprintMB))
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

    /// The log's path as a C string, worked out at launch.
    ///
    /// A signal handler may not allocate - no String, no URL, no Foundation -
    /// so the one thing it needs is prepared while it is still safe to do so.
    private static var pathBytes: [CChar] = []

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
        pathBytes = Array(fileURL.path.utf8CString)
        installSignalHandlers()
    }

    /// Catch the deaths an exception handler cannot see.
    ///
    /// An uncaught Objective-C exception is only one way to go. A Swift trap -
    /// an array index out of range, a nil unwrapped, an Int16 that will not
    /// hold what it was given - is not an exception at all; it is an
    /// instruction that stops the program, and it arrives here as a signal.
    /// The first crash this app's own log recorded had no exception line,
    /// which said what it was not and nothing about what it was.
    private static func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { number in
            Diagnostics.recordSignal(number)
            // Put the default back and go again, so iOS still writes its own
            // report. Swallowing the signal would trade their report for ours.
            Darwin.signal(number, SIG_DFL)
            raise(number)
        }
        for number in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            Darwin.signal(number, handler)
        }
    }

    /// Written with nothing but write(2) and a stack buffer, because anything
    /// that allocates can deadlock a process that is already dying.
    private static func recordSignal(_ number: Int32) {
        let path = pathBytes
        guard !path.isEmpty else { return }
        let descriptor = path.withUnsafeBufferPointer {
            open($0.baseAddress!, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        }
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }

        let label: StaticString
        switch number {
        case SIGABRT: label = "\n致命的: signal SIGABRT (中断)\n"
        case SIGILL:  label = "\n致命的: signal SIGILL (Swift のトラップの可能性)\n"
        case SIGSEGV: label = "\n致命的: signal SIGSEGV (不正なメモリ参照)\n"
        case SIGFPE:  label = "\n致命的: signal SIGFPE (演算エラー)\n"
        case SIGBUS:  label = "\n致命的: signal SIGBUS\n"
        case SIGTRAP: label = "\n致命的: signal SIGTRAP (Swift のトラップ)\n"
        default:      label = "\n致命的: signal (不明)\n"
        }
        _ = label.withUTF8Buffer { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }

        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 24)
        let count = frames.withUnsafeMutableBufferPointer {
            backtrace($0.baseAddress, Int32($0.count))
        }
        frames.withUnsafeMutableBufferPointer {
            backtrace_symbols_fd($0.baseAddress, count, descriptor)
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
    /// Running out of memory leaves no exception and no signal - the app is
    /// simply gone. A warning in the log just before an unclean exit is the
    /// only sign that is what happened.
    static func watchMemory() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            log(String(format: "警告: メモリ不足の通知（使用 %.0f MB）", footprintMB))
        }
    }

    static func end() {
        log("---- 背面へ ----")
        UserDefaults.standard.set(true, forKey: cleanKey)
    }
}
