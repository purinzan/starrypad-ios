import Foundation

/// Turns whatever note a controller sends into a pad.
///
/// The kit's own table is the mapping this app was built around, but a pad
/// controller plugged into a phone is not necessarily the one it was built
/// around, and a hit that maps to nothing is silence with no explanation.
/// So the table is tried first, then the two note blocks pad controllers
/// almost always use, and anything still unrecognised takes the next free pad
/// in the order it arrives. Every hit makes a sound.
struct NoteMap {

    /// How a note found its pad, so the UI can say which mapping is in play.
    enum Source: String {
        case kit = "Kit"
        case block = "Block"
        case learned = "Learned"
    }

    private(set) var source: Source = .kit
    private var bound: [UInt8: Int] = [:]
    private var nextFree = 0

    mutating func pad(for note: UInt8) -> Int {
        if let id = bound[note] { return id }
        if let pad = Kit.pad(forNote: note) {
            return bind(note, to: pad.id, via: .kit)
        }
        // The two blocks a 4x4 controller sends: General MIDI drums start at
        // 36, and the lower octave block starts at 20.
        if (36...51).contains(note) {
            return bind(note, to: Int(note) - 36, via: .block)
        }
        if (20...35).contains(note) {
            return bind(note, to: Int(note) - 20, via: .block)
        }
        let id = nextFree % Kit.pads.count
        nextFree += 1
        return bind(note, to: id, via: .learned)
    }

    private mutating func bind(_ note: UInt8, to id: Int, via source: Source) -> Int {
        bound[note] = id
        self.source = source
        return id
    }
}
