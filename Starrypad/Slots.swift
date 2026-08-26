import Foundation
import SwiftUI

/// Where a pad's sound comes from.
///
/// A slot either plays one of the sixteen sounds that ship in the app, or a
/// recording made on the phone. Both are just a buffer by the time they reach
/// the player; the distinction only matters for naming and for knowing which
/// files are safe to delete.
enum SoundSource: Equatable {
    case builtIn(file: String)
    case user(name: String)

    /// The key the player caches decoded audio under.
    var key: String {
        switch self {
        case .builtIn(let file): return "kit:\(file)"
        case .user(let name): return "user:\(name)"
        }
    }
}

/// One of the 64 slots: what it plays and how it sits in the mix.
struct PadSlot: Identifiable {
    var id: Int                      // 0..63
    var source: SoundSource
    var label: String
    var hue: Color

    var level: Double = 1.0          // 0...1.5
    var pan: Double = 0              // -1...1
    var tune: Int = 0                // semitones, -12...12
    var muted = false

    /// Trim, as fractions of the whole sound. Only user recordings carry one.
    var start: Double = 0
    var end: Double = 1

    var bank: Int { id / Banks.padCount }
    var positionInBank: Int { id % Banks.padCount }
    var isTrimmed: Bool { start > 0.0001 || end < 0.9999 }
}

enum Banks {
    static let padCount = 16
    static let count = 4
    static let slotCount = padCount * count
    static let names = ["A", "B", "C", "D"]

    /// Bank A holds the shipped kit; the rest start empty and get filled by
    /// sampling, which is the only way to put a new sound on a pad.
    static func initialSlots() -> [PadSlot] {
        (0..<slotCount).map { id in
            let position = id % padCount
            if id < padCount {
                let pad = Kit.pads[position]
                return PadSlot(id: id, source: .builtIn(file: pad.file),
                               label: pad.sound, hue: pad.hue)
            }
            // An empty slot still points at a real sound so a stray hit is
            // audible rather than a silent mystery; it is dimmed in the grid.
            let pad = Kit.pads[position]
            return PadSlot(id: id, source: .builtIn(file: pad.file),
                           label: pad.sound, hue: Palette.ink3)
        }
    }

    static func label(for slot: Int) -> String {
        "\(names[slot / padCount])\(slot % padCount + 1)"
    }
}

/// The slots, the selection, and which bank is on screen.
final class Rack: ObservableObject {
    @Published var slots: [PadSlot] = Banks.initialSlots()
    @Published var bank: Int = 0
    @Published var selected: Int = 0
    @Published var soloed: Set<Int> = []

    /// The sixteen slots the grid is showing, bottom left first like the pads.
    var visible: [PadSlot] {
        let base = bank * Banks.padCount
        return Array(slots[base..<(base + Banks.padCount)])
    }

    func slot(inBankPosition position: Int) -> PadSlot {
        slots[bank * Banks.padCount + position]
    }

    /// Whether a slot should be heard at all, given mutes and solos.
    func audible(_ id: Int) -> Bool {
        if !soloed.isEmpty { return soloed.contains(id) }
        return !slots[id].muted
    }

    func selectBank(_ index: Int) {
        guard index != bank, Banks.names.indices.contains(index) else { return }
        // Carry the selection to the same position in the new bank, so
        // switching banks does not also move which pad you were editing.
        let position = selected % Banks.padCount
        bank = index
        selected = index * Banks.padCount + position
    }

    func toggleMute(_ id: Int) { slots[id].muted.toggle() }

    func toggleSolo(_ id: Int) {
        if soloed.contains(id) { soloed.remove(id) } else { soloed.insert(id) }
    }

    /// Swap two pads outright: the sound and everything set about it move
    /// together, because a pad is what you hear, not where it sits.
    func swap(_ first: Int, _ second: Int) {
        guard first != second,
              slots.indices.contains(first), slots.indices.contains(second) else { return }
        let a = slots[first], b = slots[second]
        slots[first] = moved(b, to: a.id)
        slots[second] = moved(a, to: b.id)
        // Solo follows the sound, or soloing a pad then moving it would leave
        // the wrong one lit.
        let firstSoloed = soloed.contains(first), secondSoloed = soloed.contains(second)
        soloed.remove(first); soloed.remove(second)
        if firstSoloed { soloed.insert(second) }
        if secondSoloed { soloed.insert(first) }
    }

    /// Everything except the id, which belongs to the position, not the sound.
    private func moved(_ slot: PadSlot, to id: Int) -> PadSlot {
        var out = slot
        out.id = id
        return out
    }

    /// Put a chosen sound on a slot, leaving its mix alone.
    func setSound(_ source: SoundSource, label: String, on id: Int) {
        slots[id].source = source
        slots[id].label = label
        slots[id].start = 0
        slots[id].end = 1
        if case .user = source {
            slots[id].hue = Palette.signal
        } else if case .builtIn(let file) = source,
                  let pad = Kit.pads.first(where: { $0.file == file }) {
            slots[id].hue = pad.hue
        }
    }

    /// Put a freshly made recording on a slot.
    func assign(_ name: String, label: String, to id: Int) {
        slots[id].source = .user(name: name)
        slots[id].label = label
        slots[id].hue = Palette.signal
        slots[id].start = 0
        slots[id].end = 1
        slots[id].tune = 0
    }
}
