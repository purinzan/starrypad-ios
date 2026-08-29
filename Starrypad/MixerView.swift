import SwiftUI

/// Level, pan and tune for the selected pad, plus mute, solo and touch.
///
/// One pad at a time, and everything on one screen. It used to be a column of
/// full-width sliders that ran past the bottom, which is the wrong shape for a
/// mixer twice over: you scrolled to reach half the controls, and you could not
/// see what you had set without scrolling back. Three knobs side by side hold
/// the same three values in a third of the height, and they read like the panel
/// they sit on. Master and tempo left entirely - they belong next to the pads,
/// not behind a tab.
struct MixerView: View {
    @ObservedObject var rack: Rack
    @Binding var renaming: Bool
    @Binding var velocityFromForce: Bool
    @ObservedObject var force: StrikeForce
    var onTune: () -> Void
    var onAudition: () -> Void

    @FocusState private var nameFocused: Bool

    private var slot: PadSlot { rack.slots[rack.selected] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            knobs
            buttons
            touch
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(Banks.label(for: rack.selected))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accent)

            if renaming {
                TextField("Name", text: Binding(
                    get: { rack.slots[rack.selected].label },
                    set: { rack.rename(rack.selected, to: $0) }
                ))
                .font(.system(size: 15))
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { renaming = false }
                .onAppear { nameFocused = true }
            } else {
                Text(slot.label)
                    .font(.system(size: 15)).foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button { renaming.toggle() } label: {
                Image(systemName: renaming ? "checkmark" : "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(renaming ? Palette.accent : Palette.ink2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAudition) {
                ArtButton(label: "Hear", hue: Palette.accent, on: false, minHeight: 28)
                    .frame(width: 56)
            }
        }
    }

    private var knobs: some View {
        HStack(spacing: 0) {
            ArtKnob(
                value: Binding(get: { rack.slots[rack.selected].level },
                               set: { rack.slots[rack.selected].level = $0 }),
                range: 0...1.5, tint: Palette.accent, caption: "LEVEL", diameter: 40,
                reading: String(format: "%.0f%%", slot.level * 100)
            )
            .frame(maxWidth: .infinity)

            ArtKnob(
                value: Binding(get: { rack.slots[rack.selected].pan },
                               set: { rack.slots[rack.selected].pan = $0 }),
                range: -1...1, tint: Palette.signal, caption: "PAN", diameter: 40,
                reading: panLabel(slot.pan)
            )
            .frame(maxWidth: .infinity)

            ArtKnob(
                value: Binding(get: { Double(rack.slots[rack.selected].tune) },
                               set: { rack.slots[rack.selected].tune = Int($0.rounded()) }),
                range: -12...12, tint: Palette.signal, caption: "TUNE", diameter: 40,
                reading: "\(slot.tune >= 0 ? "+" : "")\(slot.tune) st",
                onCommit: onTune
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button { rack.toggleMute(rack.selected) } label: {
                ArtButton(label: "Mute", hue: Palette.danger, on: slot.muted, minHeight: 32)
            }
            Button { rack.toggleSolo(rack.selected) } label: {
                ArtButton(label: "Solo", hue: Palette.accent,
                          on: rack.soloed.contains(rack.selected), minHeight: 32)
            }
            Button {
                rack.slots[rack.selected].level = 1
                rack.slots[rack.selected].pan = 0
                rack.slots[rack.selected].tune = 0
                onTune()
            } label: {
                ArtButton(label: "Reset", hue: Palette.ink2, on: false, minHeight: 32)
            }
        }
    }

    /// Where velocity comes from, and what the sensor reads right now, on one
    /// line - it is a setting you check while playing, not a paragraph.
    private var touch: some View {
        HStack(spacing: 8) {
            Text("TOUCH").font(.system(size: 9, weight: .semibold)).kerning(1.3)
                .foregroundStyle(Palette.ink3)

            Button { if force.available { velocityFromForce.toggle() } } label: {
                ArtButton(label: velocityFromForce ? "How hard" : "Where you hit",
                          hue: Palette.accent, on: velocityFromForce,
                          enabled: force.available, minHeight: 28)
                    .frame(width: 116)
            }

            Spacer(minLength: 4)

            Text(force.available
                 ? String(format: "%.3f g \u{2192} %d", force.lastPeak, force.lastVelocity)
                 : "no sensor")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(force.lastVelocity > 0 ? Palette.signal : Palette.ink3)
        }
    }

    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.02 { return "centre" }
        return "\(pan < 0 ? "L" : "R")\(Int(abs(pan) * 100))"
    }
}
