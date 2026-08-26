import SwiftUI

/// Choose what a pad plays: any sound in the kit, or anything sampled.
///
/// Reached by holding the pad, which is where you already are when you decide
/// a pad has the wrong sound on it.
struct SoundPicker: View {
    let target: Int
    let recordings: [String]
    var onPick: (SoundSource, String) -> Void
    var onPreview: (SoundSource) -> Void
    var onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// The row that just sounded, so the speaker lights while you can hear it.
    @State private var sounding: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Kit") {
                    ForEach(Kit.pads) { pad in
                        row(source: .builtIn(file: pad.file), title: pad.sound, tint: pad.hue)
                    }
                }

                if recordings.isEmpty {
                    Section("Sampled") {
                        Text("Nothing sampled yet. The Sampler records the microphone or takes the sound out of a video.")
                            .font(.system(size: 12)).foregroundStyle(Palette.ink3)
                    }
                } else {
                    Section("Sampled") {
                        ForEach(recordings, id: \.self) { name in
                            row(source: .user(name: name),
                                title: Self.title(for: name), tint: Palette.signal)
                        }
                        .onDelete { offsets in
                            for index in offsets { onDelete(recordings[index]) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pad \(Banks.label(for: target))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Hear it, then take it.
    ///
    /// The speaker and the name are separate targets rather than one row that
    /// does both: choosing a sound means hearing several, and a list where
    /// every touch commits is a list you cannot browse.
    private func row(source: SoundSource, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(tint).frame(width: 3, height: 20)

            Button {
                sounding = source.key
                onPreview(source)
                // Long enough to read as a flash, short enough that holding a
                // finger down does not queue a stack of them.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if sounding == source.key { sounding = nil }
                }
            } label: {
                Image(systemName: sounding == source.key ? "speaker.wave.2.fill" : "play.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(sounding == source.key ? Palette.accent : Palette.ink2)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title).foregroundStyle(Palette.ink)
            Spacer()

            Button("Use") {
                onPick(source, title)
                dismiss()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .buttonStyle(.plain)
        }
    }

    /// "mic-1735689600000.wav" reads as "Mic 1"; the stamp is for uniqueness on
    /// disk, not for reading.
    static func title(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let parts = stem.split(separator: "-")
        guard let kind = parts.first else { return stem }
        let ordinal = parts.count > 1 ? String(parts[1].suffix(4)) : ""
        return "\(kind.capitalized) \(ordinal)"
    }
}
