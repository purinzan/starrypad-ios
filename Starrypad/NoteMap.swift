import Foundation

/// Turns whatever note a controller sends into a pad position, 0 to 15.
///
/// Guessing this from note numbers alone does not work, and the first attempt
/// here proved it: resolving each note independently, kit table first and note
/// blocks second, sent some notes to one coordinate system and the rest to
/// another, so the grid came out scrambled. A controller's layout is one
/// decision, not sixteen.
///
/// So there are two modes. Learned, where you hit the pads once in order and it
/// records exactly what each one sends — always right, whatever the hardware
/// does. And guessed, for before you have done that, which commits to a single
/// interpretation for the whole controller rather than mixing them.
struct NoteMap {

    enum Source: String {
        case learned = "Learned"
        case block = "Block"
        case kit = "Kit"
        case arrival = "New"
    }

    private(set) var source: Source = .block
    private var learned: [UInt8: Int] = [:]
    private var arrival: [UInt8: Int] = [:]
    private var nextFree = 0

    /// Which position the learner is waiting for, or nil when not learning.
    private(set) var learningPosition: Int?

    init() { learned = NoteMap.loadLearned() }

    var hasLearned: Bool { learned.count >= Banks.padCount }

    // MARK: - Resolving

    mutating func position(for note: UInt8) -> Int {
        if let learning = learningPosition {
            return record(note, at: learning)
        }
        if let position = learned[note] {
            source = .learned
            return position
        }
        // One interpretation for the whole controller. A 4x4 pad controller
        // sends a contiguous block; General MIDI drums start at 36 and the
        // lower block at 20. These come first precisely because mixing them
        // with the kit table is what broke the layout.
        if (36...51).contains(note) {
            source = .block
            return Int(note) - 36
        }
        if (20...35).contains(note) {
            source = .block
            return Int(note) - 20
        }
        if let pad = Kit.pad(forNote: note) {
            source = .kit
            return pad.id
        }
        if let position = arrival[note] {
            source = .arrival
            return position
        }
        let position = nextFree % Banks.padCount
        nextFree += 1
        arrival[note] = position
        source = .arrival
        return position
    }

    // MARK: - Learning

    mutating func beginLearning() {
        learned.removeAll()
        arrival.removeAll()
        nextFree = 0
        learningPosition = 0
    }

    mutating func cancelLearning() {
        learningPosition = nil
        learned = NoteMap.loadLearned()
    }

    /// Bind a note to the position being learned and move to the next.
    private mutating func record(_ note: UInt8, at position: Int) -> Int {
        // A pad hit twice should correct itself rather than consume two
        // positions, so an existing binding for this note is dropped first.
        learned = learned.filter { $0.value != position && $0.key != note }
        learned[note] = position
        source = .learned
        let next = position + 1
        learningPosition = next < Banks.padCount ? next : nil
        if learningPosition == nil { NoteMap.saveLearned(learned) }
        return position
    }

    func forget() {
        NoteMap.saveLearned([:])
    }

    // MARK: - Persistence

    private static let key = "noteMap.learned"

    private static func loadLearned() -> [UInt8: Int] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] else {
            return [:]
        }
        var out: [UInt8: Int] = [:]
        for (note, position) in raw {
            if let number = UInt8(note), (0..<Banks.padCount).contains(position) {
                out[number] = position
            }
        }
        return out
    }

    private static func saveLearned(_ map: [UInt8: Int]) {
        var raw: [String: Int] = [:]
        for (note, position) in map { raw["\(note)"] = position }
        UserDefaults.standard.set(raw, forKey: key)
    }
}
