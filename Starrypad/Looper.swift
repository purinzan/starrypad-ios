import Foundation
import QuartzCore

/// A bar-length loop you play into, ported from the desktop looper.
///
/// The desktop keeps its loop on a dedicated audio thread and stores events as
/// beat positions rather than seconds, so the tempo can move without rewriting
/// the take. This does the same on a timer queue: positions are beats, and the
/// only thing that turns them into time is the tempo read at the moment a
/// scheduling tick happens.
final class Looper: ObservableObject {

    struct Event: Identifiable {
        let id = UUID()
        var beat: Double
        var padID: Int
        var velocity: Int
    }

    enum State: Equatable {
        case idle
        case countIn          // a bar of clicks before the take begins
        case recording        // recording over the top, always also playing
        case playing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var events: [Event] = []
    @Published var bars: Int = 2 {
        didSet { events = events.filter { $0.beat < totalBeats } }
    }
    @Published var bpm: Double = 120

    /// Called on the main queue when a recorded hit comes back round.
    var onFire: ((Int, Int) -> Void)?
    /// Called on each beat of the count-in; true on the first beat of the bar.
    var onClick: ((Bool) -> Void)?

    /// Beats left in the count-in, for the transport to show.
    @Published private(set) var countRemaining = 0

    var totalBeats: Double { Double(bars * 4) }
    var canUndo: Bool { !history.isEmpty }

    private var startedAt: CFTimeInterval?
    private var countStartedAt: CFTimeInterval?
    private var playThroughCount = false
    private var lastCountBeat = -1
    private var lastPosition: Double = 0
    private var timer: DispatchSourceTimer?
    private var history: [[Event]] = []
    private let queue = DispatchQueue(label: "starrypad.looper", qos: .userInteractive)

    /// Where the playhead is, in beats. Read every frame by the UI, so it
    /// computes rather than publishes: a 60 Hz publish would redraw the world.
    var position: Double {
        guard let startedAt else { return 0 }
        let beats = (CACurrentMediaTime() - startedAt) * bpm / 60.0
        return beats.truncatingRemainder(dividingBy: totalBeats)
    }

    // MARK: - Transport

    func toggleRecord() {
        switch state {
        case .recording:
            state = .playing                 // drop out of record, keep looping
        case .countIn:
            // Pressing record during the count cancels it, and nothing that
            // was already there is touched.
            stop()
        case .playing:
            // Recording again counts in too, and the take that follows starts
            // at bar one. The tempo does not move: it is the same clock, and
            // what you already recorded keeps playing through the count.
            pushHistory()
            beginCountIn(keepPlaying: true)
        case .idle:
            pushHistory()
            beginCountIn(keepPlaying: false)
        }
    }

    /// One bar of clicks, then the take starts on the downbeat.
    ///
    /// The count has its own clock so the loop can restart at zero when it
    /// ends. Anything already recorded keeps sounding through the count when
    /// asked to, which is what makes overdubbing to a click feel like playing
    /// along rather than starting over.
    private func beginCountIn(keepPlaying: Bool) {
        countRemaining = 4
        lastCountBeat = -1
        countStartedAt = CACurrentMediaTime()
        playThroughCount = keepPlaying && !events.isEmpty
        state = .countIn
        if playThroughCount, startedAt == nil { begin() } else if !playThroughCount { begin() }
        if timer == nil { begin() }
    }

    /// How far through the count-in, 0 to 1, for the bar to show.
    var countProgress: Double {
        guard state == .countIn, let countStartedAt else { return 0 }
        let beats = (CACurrentMediaTime() - countStartedAt) * bpm / 60.0
        return max(0, min(1, beats / 4))
    }

    func togglePlay() {
        switch state {
        case .idle:
            guard !events.isEmpty else { return }
            begin()
            state = .playing
        case .playing, .recording, .countIn:
            // Play is the stop button, and it stops a count-in too: nobody
            // wants to sit through a bar they have changed their mind about.
            stop()
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        startedAt = nil
        countStartedAt = nil
        playThroughCount = false
        lastPosition = 0
        countRemaining = 0
        lastCountBeat = -1
        state = .idle
    }

    func clear() {
        guard !events.isEmpty else { return }
        pushHistory()
        events = []
        stop()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        events = previous
        if events.isEmpty { stop() }
    }

    // MARK: - Recording

    /// Stamp a hit at the playhead. Silent unless recording.
    func capture(padID: Int, velocity: Int) {
        guard state == .recording else { return }
        events.append(Event(beat: position, padID: padID, velocity: velocity))
    }

    /// Move recorded hits with the pads they were played on.
    ///
    /// Rearranging the grid should not rewrite the take: if you swap two pads
    /// because they are in the wrong place, what you already played has to
    /// follow the sound, not stay behind on the position.
    func swapPads(_ first: Int, _ second: Int) {
        guard first != second else { return }
        events = events.map { event in
            var moved = event
            if event.padID == first { moved.padID = second }
            else if event.padID == second { moved.padID = first }
            return moved
        }
    }

    // MARK: - Scheduling

    private func begin() {
        startedAt = CACurrentMediaTime()
        lastPosition = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 4 ms is well under the shortest gap a person plays and far cheaper
        // than waking for every frame.
        timer.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        if state == .countIn {
            countInTick()
            // A count over an existing take still plays it, so the scheduler
            // keeps running underneath.
            guard playThroughCount else { return }
        }
        let now = position
        let previous = lastPosition
        lastPosition = now
        guard !events.isEmpty else { return }

        // The window is normally tiny and forward; at the loop point it wraps,
        // and then it is two windows, not one.
        let due: [Event]
        if now >= previous {
            due = events.filter { $0.beat > previous && $0.beat <= now }
        } else {
            due = events.filter { $0.beat > previous || $0.beat <= now }
        }
        guard !due.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let onFire = self.onFire else { return }
            for event in due { onFire(event.padID, event.velocity) }
        }
    }

    /// The count runs on its own clock so the take can start at beat zero
    /// rather than one bar in.
    private func countInTick() {
        guard let countStartedAt else { return }
        let beats = (CACurrentMediaTime() - countStartedAt) * bpm / 60.0
        let beat = Int(beats)
        if beat > lastCountBeat, beat < 4 {
            lastCountBeat = beat
            let accent = beat == 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.countRemaining = 4 - beat
                self.onClick?(accent)
            }
        }
        guard beats >= 4 else { return }
        // Restart the clock so the downbeat you just heard is the downbeat of
        // the loop, not a bar before it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .countIn else { return }
            self.countRemaining = 0
            self.countStartedAt = nil
            self.playThroughCount = false
            self.state = .recording
            // Restart the loop clock so the take begins at bar one, beat one -
            // the beat right after the fourth click.
            self.begin()
        }
    }

    private func pushHistory() {
        history.append(events)
        if history.count > 20 { history.removeFirst() }
    }
}
