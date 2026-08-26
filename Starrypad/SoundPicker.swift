import SwiftUI

/// Choose what a pad plays: any sound in the kit, or anything sampled.
///
/// Reached by holding the pad, which is where you already are when you decide
/// a pad has the wrong sound on it.
struct SoundPicker: View {
    let target: Int
    let recordings: [String]
    var onPick: (SoundSource, String) -> Void
    var onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Kit") {
                    ForEach(Kit.pads) { pad in
                        Button {
                            onPick(.builtIn(file: pad.file), pad.sound)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Rectangle().fill(pad.hue).frame(width: 3, height: 20)
                                Text(pad.sound).foregroundStyle(Palette.ink)
                                Spacer()
                            }
                        }
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
                            Button {
                                onPick(.user(name: name), Self.title(for: name))
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Rectangle().fill(Palette.signal).frame(width: 3, height: 20)
                                    Text(Self.title(for: name)).foregroundStyle(Palette.ink)
                                    Spacer()
                                }
                            }
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
