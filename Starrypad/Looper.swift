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
        /// Which time round the loop this was played on. Undo peels one pass
        /// at a time, so an overdub that went wrong costs you that pass and
        /// not the whole take.
        var pass: Int = 0
    }

    enum State: Equatable {
        case idle
        case countIn          // a bar of clicks before the take begins
        case recording        // recording over the top, always also playing
        case playing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var events: [Event] = [] {
        didSet { publishSchedule() }
    }

    /// The take as the scheduler sees it.
    ///
    /// `events` is published and belongs to the main thread; the tick runs on
    /// its own queue every millisecond and used to read the same array. One
    /// thread growing a Swift array while another iterates it is a
    /// use-after-free waiting for a busy bar - the kind of crash that arrives
    /// once in a hundred takes and never where you are looking. The scheduler
    /// reads its own copy instead, swapped under a lock whenever the take
    /// changes. Copying is a retain, not a copy: the storage is shared until
    /// one of them writes.
    private var schedule: [Event] = []
    private let scheduleLock = NSLock()

    private func publishSchedule() {
        let snapshot = events
        scheduleLock.lock()
        schedule = snapshot
        scheduleLock.unlock()
    }

    private var scheduled: [Event] {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        return schedule
    }
    /// How long the loop is, in bars.
    ///
    /// Changing it throws nothing away. Shrinking used to delete every hit
    /// past the new end, which meant trying a one bar version of a four bar
    /// idea destroyed three bars of playing for a tap - and taps are not
    /// decisions. What lies beyond the end simply does not sound; grow the
    /// loop again and it all comes back.
    @Published var bars: Int = UserDefaults.standard.object(forKey: "loop.bars") as? Int ?? 2 {
        didSet {
            guard bars != oldValue else { return }
            UserDefaults.standard.set(bars, forKey: "loop.bars")
            holdPlace()
        }
    }

    static let lengths = [1, 2, 4, 8]

    func cycleLength() {
        let next = (Self.lengths.firstIndex(of: bars).map { $0 + 1 } ?? 1) % Self.lengths.count
        bars = Self.lengths[next]
    }

    /// Keep the playhead where it is in the bar when the loop changes length.
    ///
    /// Position is elapsed time folded by the loop length, so changing the
    /// length alone would throw the playhead somewhere arbitrary. Re-anchoring
    /// holds the place and only changes where the fold happens.
    private func holdPlace() {
        guard let started = startedAt else { return }
        let now = CACurrentMediaTime()
        let elapsed = (now - started) * bpm / 60.0
        let place = elapsed.truncatingRemainder(dividingBy: totalBeats)
        startedAt = now - place * 60.0 / bpm
        lastPosition = place
    }
    @Published var bpm: Double = UserDefaults.standard.object(forKey: "loop.bpm") as? Double ?? 120 {
        didSet {
            reanchor(from: oldValue)
            UserDefaults.standard.set(bpm, forKey: "loop.bpm")
        }
    }

    /// Keep the playhead where it is when the tempo changes.
    ///
    /// Position is elapsed time read at the current tempo, so changing the
    /// tempo alone would move it - a loop playing at bar three would jump
    /// somewhere else the moment you turned the knob. Re-anchoring the start
    /// time holds the beat still and only changes how fast the next one
    /// arrives, which is what turning a tempo knob is supposed to do.
    private func reanchor(from oldBPM: Double) {
        guard oldBPM > 0, bpm > 0, oldBPM != bpm else { return }
        let now = CACurrentMediaTime()
        if let started = startedAt {
            let beats = (now - started) * oldBPM / 60.0
            startedAt = now - beats * 60.0 / bpm
        }
        if let counting = countStartedAt {
            let beats = (now - counting) * oldBPM / 60.0
            countStartedAt = now - beats * 60.0 / bpm
        }
    }

    /// Called on the main queue when a recorded hit comes back round.
    var onFire: ((Int, Int) -> Void)?
    /// Called on each beat of the count-in; true on the first beat of the bar.
    var onClick: ((Bool) -> Void)?

    /// Beats left in the count-in, for the transport to show.
    @Published private(set) var countRemaining = 0

    /// Keep clicking all the way through the take, not just the count.
    ///
    /// Off by default: a click under everything you play is a rehearsal-room
    /// habit, not a thing everyone wants. On, it is the same click the count
    /// uses, on every beat, accented on the bar.
    @Published var clickThrough = UserDefaults.standard.bool(forKey: "click.through") {
        didSet { UserDefaults.standard.set(clickThrough, forKey: "click.through") }
    }

    /// Whether a bar of clicks comes before the take.
    ///
    /// On by default, because the first take needs somewhere to start from.
    /// Off is for the fifth overdub, where the bar you are counting is a bar
    /// you have already heard four times.
    @Published var countsIn = UserDefaults.standard.object(forKey: "count.in") as? Bool ?? true {
        didSet { UserDefaults.standard.set(countsIn, forKey: "count.in") }
    }

    /// Record has been asked for while the loop is playing, and is waiting for
    /// the bar line to come round.
    @Published private(set) var armed = false

    /// Where the bar should draw its playhead, 0 to 1, published every frame
    /// while anything is running.
    ///
    /// The bar used to read a computed position inside a TimelineView, which
    /// leaves whether it redraws up to SwiftUI. A playhead that stops moving
    /// is worse than one that costs a little to publish, so the looper drives
    /// it: one value, sixty times a second, only while running.
    @Published private(set) var sweep: Double = 0

    var totalBeats: Double { Double(bars * 4) }
    var canUndo: Bool { !events.isEmpty || !history.isEmpty }

    /// Bar, beat and sixteenth, the way a sequencer says where it is.
    var barBeatText: String {
        guard state != .idle else { return "\u{2013}" }
        if state == .countIn { return "\(countRemaining)" }
        let beats = position
        let bar = Int(beats / 4) + 1
        let beat = Int(beats.truncatingRemainder(dividingBy: 4)) + 1
        let sixteenth = Int((beats * 4).truncatingRemainder(dividingBy: 4)) + 1
        return "\(bar).\(beat).\(sixteenth)"
    }

    /// How many layers of playing are stacked in the take.
    ///
    /// It used to count times round the loop, which measures how long you have
    /// been listening rather than how much you have played: sit through a two
    /// bar loop for half a minute and it said fifteen. Worse, it disagreed
    /// with the button beside it - undo peels the newest layer off, and the
    /// newest layer might be the third. This counts what is actually there,
    /// so the number and the button mean the same thing.
    var layers: Int { Set(events.map(\.pass)).count }

    /// How many times round the loop has gone since recording started.
    private var currentPass: Int {
        guard let startedAt else { return 0 }
        let beats = (CACurrentMediaTime() - startedAt) * bpm / 60.0
        return max(0, Int(beats / totalBeats))
    }

    private var startedAt: CFTimeInterval?
    private var countStartedAt: CFTimeInterval?
    private var playThroughCount = false
    /// The count was placed against the loop rather than started from cold, so
    /// the handover must not restart the clock.
    private var alignedCount = false
    private var lastClickBeat = -1
    private var lastArmRemaining: Double?
    private var lastCountBeat = -1
    private var lastSweepAt: CFTimeInterval = 0
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
            // Not now - on the bar. Dropping into a count the instant the
            // button is pressed cuts the music in half wherever your thumb
            // happened to land. Instead the loop keeps running, the count
            // starts a bar before the wrap, and recording begins on beat one
            // with nothing about the sound having changed.
            if armed {
                armed = false                // pressed twice: never mind
                lastArmRemaining = nil
            } else {
                pushHistory()
                lastArmRemaining = nil
                armed = true
            }
        case .idle:
            pushHistory()
            guard countsIn else {
                begin()
                state = .recording
                return
            }
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
        alignedCount = false
        playThroughCount = keepPlaying && !events.isEmpty
        state = .countIn
        // One clock either way: the count reads its own start time, and the
        // loop clock is restarted when the count hands over.
        if !playThroughCount || timer == nil { begin() }
        countStartedAt = CACurrentMediaTime()
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
        alignedCount = false
        armed = false
        lastClickBeat = -1
        lastArmRemaining = nil
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

    /// Peel the most recent pass, newest first.
    ///
    /// Undoing a whole take because one overdub went wrong is the behaviour
    /// of a text editor, not an instrument: you keep playing over a loop until
    /// something lands badly, and what you want back is the last time round -
    /// not everything since you pressed record.
    func undo() {
        if let newest = events.map(\.pass).max() {
            events.removeAll { $0.pass == newest }
            if events.isEmpty, history.isEmpty { stop() }
            return
        }
        // Nothing left to peel: fall back to whatever was there before, which
        // is how a cleared take comes back.
        guard let previous = history.popLast() else { return }
        events = previous
        if events.isEmpty { stop() }
    }

    // MARK: - Recording

    /// Stamp a hit at the playhead. Silent unless recording.
    func capture(padID: Int, velocity: Int) {
        switch state {
        case .recording:
            // A hit a hair before the loop point belongs at the top of the
            // next bar, not at the very end of this one where it will play a
            // whole loop late. Drummers play ahead of the beat; this is the
            // same rounding a sequencer does at the wrap.
            let now = position
            let wrapping = now > totalBeats - Self.aheadOfBeat
            // A hit rounded forward onto the next downbeat belongs to the pass
            // it will play in, not the one it was struck in.
            let beat = wrapping ? 0 : now
            let pass = currentPass + (wrapping ? 1 : 0)
            events.append(Event(beat: beat, padID: padID, velocity: velocity, pass: pass))

        case .countIn:
            // The count-in hands over asynchronously, so for a few
            // milliseconds after the fourth click the state still says
            // counting while the player is already on beat one. A hit landing
            // there was thrown away - exactly the hit that starts the take.
            guard let startedCountAt = countStartedAt else {
                events.append(Event(beat: 0, padID: padID, velocity: velocity, pass: 0))
                return
            }
            let beats = (CACurrentMediaTime() - startedCountAt) * bpm / 60.0
            guard beats > 4 - Self.aheadOfBeat else { return }
            events.append(Event(beat: 0, padID: padID, velocity: velocity, pass: 0))

        case .idle, .playing:
            return
        }
    }

    /// How far ahead of a downbeat still counts as on it, in beats. A twelfth
    /// of a beat is about 60 ms at 90 bpm - inside human timing, outside
    /// anything anyone plays deliberately.
    private static let aheadOfBeat = 1.0 / 12

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
        // Cancel first. Without this every call left its predecessor running,
        // so restarting the clock added a timer rather than replacing one, and
        // several of them resetting startedAt in turn pinned the playhead at
        // zero however long you recorded.
        timer?.cancel()
        timer = nil
        startedAt = CACurrentMediaTime()
        lastPosition = 0
        lastClickBeat = -1
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Every millisecond. The tick is what quantises everything the loop
        // does - clicks, recorded hits, the handover - so its period is the
        // error budget for all of them. At 4 ms a click could sit 4 ms from
        // the note it is counting; at 1 ms nothing here is off by more than
        // a millisecond, which is under any threshold worth arguing about.
        // The work per tick is a comparison and a filter.
        timer.schedule(deadline: .now(), repeating: .milliseconds(1),
                       leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        publishSweep()
        if armed, state == .playing { armIfDue() }
        if state == .countIn {
            countInTick()
            // A count over an existing take still plays it, so the scheduler
            // keeps running underneath.
            guard playThroughCount else { return }
        }
        let now = position
        let previous = lastPosition
        lastPosition = now
        if state == .recording, clickThrough { clickTick(at: now) }
        let take = scheduled
        guard !take.isEmpty else { return }

        // The window is normally tiny and forward; at the loop point it wraps,
        // and then it is two windows, not one.
        let due: [Event]
        let inside = take.filter { $0.beat < totalBeats }
        if now >= previous {
            due = inside.filter { $0.beat > previous && $0.beat <= now }
        } else {
            due = inside.filter { $0.beat > previous || $0.beat <= now }
        }
        guard !due.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let onFire = self.onFire else { return }
            for event in due { onFire(event.padID, event.velocity) }
        }
    }

    /// Wait for the moment a whole bar of count fits before the loop comes
    /// round, then start it there.
    ///
    /// The count is a count of four, not however many beats happen to be left
    /// when your thumb lands. So arming waits - through the rest of this lap
    /// if it has to - for the playhead to cross the point exactly four beats
    /// from the wrap, and starts there. Four clicks, then bar one, and the
    /// loop underneath never moves.
    private func armIfDue() {
        guard let startedAt else { return }
        let secondsPerBeat = 60.0 / bpm
        let elapsed = (CACurrentMediaTime() - startedAt) / secondsPerBeat
        let remaining = totalBeats - elapsed.truncatingRemainder(dividingBy: totalBeats)
        let previous = lastArmRemaining
        lastArmRemaining = remaining
        // One sample is needed before a crossing can be seen at all.
        guard let previous else { return }
        // Remaining counts down to zero and jumps back up at the wrap.
        let wrapped = remaining > previous
        // With no count wanted, the wrap itself is the moment: the loop comes
        // round and recording is simply on, with nothing in between.
        guard countsIn else {
            guard wrapped else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .playing, self.armed else { return }
                self.armed = false
                self.lastArmRemaining = nil
                self.lastClickBeat = -1
                self.state = .recording
            }
            return
        }
        let crossing = previous > 4 && remaining <= 4
        // A one-bar loop is never more than four beats from its own wrap, so
        // there the count starts at the wrap itself.
        guard crossing || (wrapped && totalBeats <= 4) else { return }
        let short = max(0, 4 - remaining)
        countStartedAt = CACurrentMediaTime() - short * secondsPerBeat
        lastCountBeat = -1
        playThroughCount = true
        alignedCount = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .playing, self.armed else { return }
            self.armed = false
            self.lastArmRemaining = nil
            self.countRemaining = 4
            self.state = .countIn
        }
    }

    /// One click per beat under the take, accented on the bar.
    private func clickTick(at beats: Double) {
        let beat = Int(beats)
        guard beat != lastClickBeat else { return }
        // Switching the click on halfway through a beat must not produce a
        // click halfway through a beat. With nothing to compare against, take
        // the beat silently and start on the next one - unless we are standing
        // on a beat already, which is where the count hands the take over and
        // the downbeat is owed a click.
        if lastClickBeat == -1, beats - Double(beat) > 0.05 {
            lastClickBeat = beat
            return
        }
        lastClickBeat = beat
        let accent = beat % 4 == 0
        DispatchQueue.main.async { [weak self] in self?.onClick?(accent) }
    }

    /// The count runs on its own clock so the take can start at beat zero
    /// rather than one bar in.
    private func countInTick() {
        guard let startedCountAt = countStartedAt else { return }
        let beats = (CACurrentMediaTime() - startedCountAt) * bpm / 60.0
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
        // Close the count here, on the tick's own thread. The tick runs every
        // 4 ms and the handover is asynchronous, so without this it queues a
        // fresh start on every tick until the first one lands - a thousand of
        // them across one bar, each restarting the clock.
        countStartedAt = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .countIn else { return }
            self.countRemaining = 0
            self.countStartedAt = nil
            self.playThroughCount = false
            self.state = .recording
            // An aligned count was laid over a loop that never stopped, and
            // the wrap it was counting towards has just happened on its own.
            // Restarting the clock here is what would move the music.
            if self.alignedCount {
                self.alignedCount = false
                self.lastClickBeat = -1
            } else {
                // Restart the loop clock so the take begins at bar one, beat
                // one - the beat right after the fourth click.
                self.begin()
            }
        }
    }

    /// One published value per display frame, not per 4 ms audio tick.
    private func publishSweep() {
        let now = CACurrentMediaTime()
        guard now - lastSweepAt >= 1.0 / 60 else { return }
        lastSweepAt = now
        let value: Double
        switch state {
        case .countIn: value = countProgress
        case .recording, .playing: value = position / totalBeats
        case .idle: value = 0
        }
        DispatchQueue.main.async { [weak self] in self?.sweep = value }
    }

    private func pushHistory() {
        history.append(events)
        if history.count > 20 { history.removeFirst() }
    }
}
