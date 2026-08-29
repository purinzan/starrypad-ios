import AVFoundation
import Foundation
import SwiftUI

/// Getting the take out of the app.
///
/// The one thing the app could not do. Everything needed was already here: the
/// sounds are decoded buffers and the take is a list of beats, pads and
/// velocities, which is a MIDI file with the commas moved. Both forms are
/// written, because they answer different questions - a wav is "let me hear it
/// on the way home", a MIDI file is "let me finish this properly on Saturday".
enum Export {

    enum Failure: LocalizedError {
        case emptyTake
        case couldNotWrite

        var errorDescription: String? {
            switch self {
            case .emptyTake: return "There is nothing recorded to send"
            case .couldNotWrite: return "Could not write the file"
            }
        }
    }

    /// Where exports live. Replaced each time rather than accumulated: these
    /// are handed straight to the share sheet, and a folder of stale bounces
    /// is a folder nobody ever cleans.
    private static var directory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func filename(_ extension: String, bpm: Double) -> URL {
        directory.appendingPathComponent("starrypad-\(Int(bpm.rounded()))bpm.\(`extension`)")
    }

    // MARK: - Audio

    /// Bounce the loop to a 16-bit wav, exactly one loop long.
    ///
    /// A hit near the end rings past the end, and the tail is wrapped back to
    /// the top rather than cut off or left hanging - that is what makes the
    /// file loop seamlessly when it is dropped into anything else, and a
    /// cymbal that stops dead at the bar line is the sound of a bad bounce.
    static func wav(events: [Looper.Event], bars: Int, bpm: Double,
                    slots: [PadSlot], audible: (Int) -> Bool,
                    player: SamplePlayer) throws -> URL {
        guard !events.isEmpty else { throw Failure.emptyTake }

        let rate = 48000.0
        let secondsPerBeat = 60.0 / bpm
        let frames = Int((Double(bars * 4) * secondsPerBeat * rate).rounded())
        guard frames > 0 else { throw Failure.couldNotWrite }

        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)

        for event in events {
            guard slots.indices.contains(event.padID), audible(event.padID) else { continue }
            let slot = slots[event.padID]
            guard let buffer = player.exportBuffer(for: slot),
                  let source = buffer.floatChannelData else { continue }

            let gain = Velocity.gain(event.velocity) * Float(slot.level)
            let pan = Float(max(-1, min(1, slot.pan)))
            let gainLeft = gain * min(1, 1 - pan)
            let gainRight = gain * min(1, 1 + pan)
            let channels = Int(buffer.format.channelCount)
            let start = Int((event.beat * secondsPerBeat * rate).rounded())

            for frame in 0..<Int(buffer.frameLength) {
                let position = (start + frame) % frames
                let l = source[0][frame]
                let r = channels > 1 ? source[1][frame] : l
                left[position] += l * gainLeft
                right[position] += r * gainRight
            }
        }

        // The master knob is a node in the live graph, so the file has to be
        // told about it separately or the bounce comes out quieter than the
        // thing you were just listening to.
        let master = pow(10, player.makeupDecibels / 20)
        var pcm = Data(capacity: frames * 4)
        for frame in 0..<frames {
            for sample in [left[frame], right[frame]] {
                // The same saturation the limiter applies on the way out.
                let value = tanh(sample * master)
                // A NaN reaching Int16 is a crash, not a loud noise, and the
                // clamp above lets one straight through: every comparison
                // against NaN is false.
                let scaled = value.isFinite
                    ? Int16(max(-32767, min(32767, value * 32767)))
                    : 0
                withUnsafeBytes(of: scaled.littleEndian) { pcm.append(contentsOf: $0) }
            }
        }

        let url = filename("wav", bpm: bpm)
        do {
            try writeWAV(pcm, to: url, sampleRate: Int(rate), channels: 2)
        } catch {
            throw Failure.couldNotWrite
        }
        return url
    }

    // MARK: - MIDI

    /// A one-track standard MIDI file on the drum channel.
    ///
    /// Note numbers follow the General MIDI percussion map, taken from the
    /// sound rather than the position, so a kick that has been dragged to
    /// another pad still arrives as a kick. A recording has no note of its own
    /// and gets its position's.
    static func midi(events: [Looper.Event], bars: Int, bpm: Double,
                     slots: [PadSlot]) throws -> URL {
        guard !events.isEmpty else { throw Failure.emptyTake }

        let division = 480                       // ticks per quarter note
        let sorted = events.sorted { $0.beat < $1.beat }

        struct Moment { let tick: Int; let on: Bool; let note: UInt8; let velocity: UInt8 }
        var moments: [Moment] = []
        for event in sorted {
            guard slots.indices.contains(event.padID) else { continue }
            let note = generalMIDINote(for: slots[event.padID])
            let tick = Int((event.beat * Double(division)).rounded())
            let velocity = UInt8(max(1, min(127, event.velocity)))
            moments.append(Moment(tick: tick, on: true, note: note, velocity: velocity))
            // A drum hit has no length worth recording; an eighth of a beat is
            // long enough for every sequencer to show it as a note.
            moments.append(Moment(tick: tick + division / 8, on: false, note: note, velocity: 0))
        }
        moments.sort { $0.tick == $1.tick ? (!$0.on && $1.on) : $0.tick < $1.tick }

        var track = Data()
        // Tempo, so the file opens at the speed it was played at.
        let microsecondsPerQuarter = Int(60_000_000.0 / bpm)
        track.append(contentsOf: [0x00, 0xFF, 0x51, 0x03])
        track.append(contentsOf: [UInt8((microsecondsPerQuarter >> 16) & 0xFF),
                                  UInt8((microsecondsPerQuarter >> 8) & 0xFF),
                                  UInt8(microsecondsPerQuarter & 0xFF)])
        track.append(contentsOf: [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])  // 4/4

        var previous = 0
        for moment in moments {
            track.append(variableLength(moment.tick - previous))
            previous = moment.tick
            track.append(moment.on ? 0x99 : 0x89)          // channel 10
            track.append(moment.note)
            track.append(moment.velocity)
        }
        // End the file on the bar line, so the loop length survives the trip.
        let end = bars * 4 * division
        track.append(variableLength(max(0, end - previous)))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        var file = Data()
        file.append(contentsOf: Array("MThd".utf8))
        file.append(contentsOf: [0, 0, 0, 6, 0, 0, 0, 1])   // format 0, one track
        file.append(contentsOf: [UInt8(division >> 8), UInt8(division & 0xFF)])
        file.append(contentsOf: Array("MTrk".utf8))
        let length = UInt32(track.count)
        withUnsafeBytes(of: length.bigEndian) { file.append(contentsOf: $0) }
        file.append(track)

        let url = filename("mid", bpm: bpm)
        do {
            try file.write(to: url)
        } catch {
            throw Failure.couldNotWrite
        }
        return url
    }

    /// The standard percussion map, by sound.
    private static func generalMIDINote(for slot: PadSlot) -> UInt8 {
        if case .builtIn(let file) = slot.source,
           let pad = Kit.all.first(where: { $0.file == file }) {
            switch pad.sound.lowercased() {
            case let name where name.contains("kick"):       return 36
            case let name where name.contains("snare"):      return 38
            case let name where name.contains("rim"):        return 37
            case let name where name.contains("clap"):       return 39
            case let name where name.contains("closed hat"): return 42
            case let name where name.contains("open hat"):   return 46
            case let name where name.contains("floor tom"):  return 41
            case let name where name.contains("low tom"):    return 45
            case let name where name.contains("mid tom"):    return 47
            case let name where name.contains("high tom"):   return 50
            case let name where name.contains("crash"):      return 49
            case let name where name.contains("ride"):       return 51
            case let name where name.contains("cowbell"):    return 56
            case let name where name.contains("tamb"):       return 54
            case let name where name.contains("shaker"):     return 70
            case let name where name.contains("clave"):      return 75
            default: break
            }
        }
        // Anything the map does not know - a recording, a glass sound - lands
        // above the standard kit rather than on top of a real instrument.
        return UInt8(min(127, 60 + slot.positionInBank))
    }

    private static func variableLength(_ value: Int) -> Data {
        var value = max(0, value)
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8((value & 0x7F) | 0x80), at: 0)
            value >>= 7
        }
        return Data(bytes)
    }

    /// The same 44-byte header the video import writes, for the same reason.
    private static func writeWAV(_ pcm: Data, to url: URL, sampleRate: Int, channels: Int) throws {
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        let byteRate = sampleRate * channels * 2
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(channels * 2))
        append(UInt16(16))
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        try (header + pcm).write(to: url)
    }
}

/// sheet(item:) needs something Identifiable, and a URL is not.
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet. Where a file goes is the phone's decision to
/// offer and the player's to make; the app's only job is to hand over a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
