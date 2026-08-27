import SwiftUI

/// Pad layout and kit contents, generated from the desktop app so the two do
/// not drift. Acoustic sounds are the Salamander Drumkit (CC BY 3.0); the
/// electronic ones are the CC0 TR-808 set. See LICENSE-SAMPLES.
struct Pad: Identifiable {
    let id: Int
    let name: String
    let sound: String
    let file: String
    let hue: Color
    let note: UInt8?

    /// How the desktop balances this sound inside its kit.
    var gain: Double = 1.0
    var tune: Int = 0
    /// Some sounds are a shortened take of a longer one - a clap off a snare,
    /// a shaker off a hat. nil means play the whole thing.
    var milliseconds: Int? = nil
}

enum Kit {
    /// Bank A. Pad 0 is bottom left, matching the hardware and the desktop grid.
    static let acoustic: [Pad] = [
        Pad(id: 0, name: "Kick", sound: "Kick",
            file: "ac_kick_OH_FF_6.wav",
            hue: Color(red: 0.847, green: 0.345, blue: 0.247), note: nil,
            gain: 1.00, tune: 0, milliseconds: nil),
        Pad(id: 1, name: "Snare", sound: "Snare",
            file: "ac_snare_OH_FF_3.wav",
            hue: Color(red: 0.208, green: 0.435, blue: 0.702), note: nil,
            gain: 0.98, tune: 0, milliseconds: nil),
        Pad(id: 2, name: "Closed Hat", sound: "Closed Hat",
            file: "ac_hihatClosed_OH_F_1.wav",
            hue: Color(red: 0.180, green: 0.490, blue: 0.357), note: nil,
            gain: 0.78, tune: 0, milliseconds: 130),
        Pad(id: 3, name: "Open Hat", sound: "Open Hat",
            file: "ac_hihatOpen_OH_FF_1.wav",
            hue: Color(red: 0.110, green: 0.482, blue: 0.569), note: nil,
            gain: 0.78, tune: 0, milliseconds: nil),
        Pad(id: 4, name: "Low Tom", sound: "Low Tom",
            file: "ac_loTom_OH_FF_1.wav",
            hue: Color(red: 0.467, green: 0.322, blue: 0.639), note: nil,
            gain: 0.98, tune: -3, milliseconds: nil),
        Pad(id: 5, name: "Mid Tom", sound: "Mid Tom",
            file: "ac_hiTom_OH_FF_1.wav",
            hue: Color(red: 0.816, green: 0.604, blue: 0.141), note: nil,
            gain: 0.94, tune: 0, milliseconds: nil),
        Pad(id: 6, name: "High Tom", sound: "High Tom",
            file: "ac_hiTom_OH_FF_1.wav",
            hue: Color(red: 0.690, green: 0.424, blue: 0.180), note: nil,
            gain: 0.92, tune: 3, milliseconds: nil),
        Pad(id: 7, name: "Floor Tom", sound: "Floor Tom",
            file: "ac_loTom_OH_FF_1.wav",
            hue: Color(red: 0.373, green: 0.353, blue: 0.635), note: nil,
            gain: 1.02, tune: -6, milliseconds: nil),
        Pad(id: 8, name: "Clap", sound: "Clap",
            file: "ac_snare2_OH_MP_5.wav",
            hue: Color(red: 0.608, green: 0.310, blue: 0.247), note: nil,
            gain: 0.24, tune: 0, milliseconds: 90),
        Pad(id: 9, name: "Rim", sound: "Rim",
            file: "ac_snareStick_OH_F_5.wav",
            hue: Color(red: 0.702, green: 0.227, blue: 0.337), note: nil,
            gain: 0.72, tune: 0, milliseconds: 85),
        Pad(id: 10, name: "Cowbell", sound: "Cowbell",
            file: "ac_cowbell_FF_1.wav",
            hue: Color(red: 0.502, green: 0.443, blue: 0.165), note: nil,
            gain: 0.82, tune: 0, milliseconds: nil),
        Pad(id: 11, name: "Crash", sound: "Crash",
            file: "ac_crash1_OH_FF_5.wav",
            hue: Color(red: 0.337, green: 0.439, blue: 0.435), note: nil,
            gain: 0.82, tune: 0, milliseconds: nil),
        Pad(id: 12, name: "Ride", sound: "Ride",
            file: "ac_ride1_OH_FF_2.wav",
            hue: Color(red: 0.424, green: 0.498, blue: 0.600), note: nil,
            gain: 0.72, tune: 0, milliseconds: 1500),
        Pad(id: 13, name: "Tamb", sound: "Tamb",
            file: "ac_hihatSemiOpen7_OH_F_4.wav",
            hue: Color(red: 0.753, green: 0.408, blue: 0.541), note: nil,
            gain: 0.22, tune: 0, milliseconds: 110),
        Pad(id: 14, name: "Shaker", sound: "Shaker",
            file: "ac_hihatClosed_OH_F_1.wav",
            hue: Color(red: 0.298, green: 0.549, blue: 0.455), note: nil,
            gain: 0.50, tune: 0, milliseconds: 60),
        Pad(id: 15, name: "Clave", sound: "Clave",
            file: "ac_snareStick_OH_F_5.wav",
            hue: Color(red: 0.541, green: 0.384, blue: 0.267), note: nil,
            gain: 0.52, tune: 0, milliseconds: 55)
    ]

    /// Bank B: where the sounds that used to be bank A now live.
    static let electronic: [Pad] = [
        Pad(id: 0, name: "Kick", sound: "808 Kick Long",
            file: "kick8_long.wav",
            hue: Color(red: 0.847, green: 0.345, blue: 0.247), note: 35),
        Pad(id: 1, name: "Snare", sound: "808 Snare",
            file: "snare8.wav",
            hue: Color(red: 0.208, green: 0.435, blue: 0.702), note: 38),
        Pad(id: 2, name: "Closed Hat", sound: "808 Hat",
            file: "hat8.wav",
            hue: Color(red: 0.180, green: 0.490, blue: 0.357), note: 42),
        Pad(id: 3, name: "Open Hat", sound: "808 Open Hat",
            file: "openhat8.wav",
            hue: Color(red: 0.110, green: 0.482, blue: 0.569), note: 46),
        Pad(id: 4, name: "Low Tom", sound: "808 Low Tom",
            file: "lowtom8.wav",
            hue: Color(red: 0.467, green: 0.322, blue: 0.639), note: 45),
        Pad(id: 5, name: "Mid Tom", sound: "808 Mid Tom",
            file: "midtom8.wav",
            hue: Color(red: 0.816, green: 0.604, blue: 0.141), note: 48),
        Pad(id: 6, name: "High Tom", sound: "808 High Tom",
            file: "hitom8.wav",
            hue: Color(red: 0.690, green: 0.424, blue: 0.180), note: 50),
        Pad(id: 7, name: "Floor Tom", sound: "808 Conga",
            file: "conga8.wav",
            hue: Color(red: 0.373, green: 0.353, blue: 0.635), note: 41),
        Pad(id: 8, name: "Clap", sound: "808 Clap",
            file: "clap8.wav",
            hue: Color(red: 0.608, green: 0.310, blue: 0.247), note: 39),
        Pad(id: 9, name: "Rim", sound: "808 Rim",
            file: "rim8.wav",
            hue: Color(red: 0.702, green: 0.227, blue: 0.337), note: 37),
        Pad(id: 10, name: "Cowbell", sound: "808 Cowbell",
            file: "cowbell8.wav",
            hue: Color(red: 0.502, green: 0.443, blue: 0.165), note: 56),
        Pad(id: 11, name: "Crash", sound: "Glass Shatter",
            file: "glass_shatter_1.wav",
            hue: Color(red: 0.376, green: 0.651, blue: 0.729), note: 49),
        Pad(id: 12, name: "Ride", sound: "808 Cymbal",
            file: "cymbal8.wav",
            hue: Color(red: 0.337, green: 0.439, blue: 0.435), note: 51),
        Pad(id: 13, name: "Tamb", sound: "Glass Break",
            file: "glass_break_1.wav",
            hue: Color(red: 0.471, green: 0.729, blue: 0.784), note: 54),
        Pad(id: 14, name: "Shaker", sound: "808 Maraca",
            file: "maraca8.wav",
            hue: Color(red: 0.298, green: 0.549, blue: 0.455), note: 70),
        Pad(id: 15, name: "Clave", sound: "Glass Tap",
            file: "glass_tap_1.wav",
            hue: Color(red: 0.588, green: 0.804, blue: 0.839), note: 75),
    ]

    /// What bank A starts as, and what the note table is keyed on.
    static let pads: [Pad] = acoustic

    /// Everything the sound picker can offer.
    static let all: [Pad] = acoustic + electronic

    /// Which sounds share an instrument and so cannot ring together.
    ///
    /// Only the hats, because they are the only pair on a kit where one is
    /// physically the other: a closed hat is an open hat with the pedal down.
    /// Toms and cymbals really can ring at the same time.
    static func chokeGroup(for pad: Pad) -> String? {
        pad.sound.lowercased().contains("hat") ? "hihat" : nil
    }

    static func pad(forNote note: UInt8) -> Pad? {
        electronic.first { $0.note == note }
    }
}
