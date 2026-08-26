import SwiftUI

/// Level, pan and tune for the selected pad, plus mute and solo.
///
/// One pad at a time rather than sixteen strips: a phone has no room for a
/// console, and the pad you are editing is the one you just hit.
struct MixerView: View {
    @ObservedObject var rack: Rack
    @Binding var master: Double
    var onTune: () -> Void
    var onAudition: () -> Void
    var onMaster: () -> Void

    private var slot: PadSlot { rack.slots[rack.selected] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Banks.label(for: rack.selected))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                Text(slot.label).font(.system(size: 15)).foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Button("Hear", action: onAudition)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }

            knobRow("MASTER", value: String(format: "%+.0f dB", master)) {
                Slider(value: $master, in: 0...12, step: 0.5,
                       onEditingChanged: { editing in if !editing { onMaster() } })
                    .tint(Palette.danger)
            }

            knobRow("LEVEL", value: String(format: "%.0f%%", slot.level * 100)) {
                Slider(value: Binding(
                    get: { rack.slots[rack.selected].level },
                    set: { rack.slots[rack.selected].level = $0 }
                ), in: 0...1.5)
                .tint(Palette.accent)
            }

            knobRow("PAN", value: panLabel(slot.pan)) {
                Slider(value: Binding(
                    get: { rack.slots[rack.selected].pan },
                    set: { rack.slots[rack.selected].pan = $0 }
                ), in: -1...1)
                .tint(Palette.signal)
            }

            knobRow("TUNE", value: "\(slot.tune >= 0 ? "+" : "")\(slot.tune) st") {
                Slider(
                    value: Binding(
                        get: { Double(rack.slots[rack.selected].tune) },
                        set: { rack.slots[rack.selected].tune = Int($0.rounded()) }
                    ),
                    in: -12...12, step: 1,
                    onEditingChanged: { editing in if !editing { onTune() } }
                )
                .tint(Palette.signal)
            }

            HStack(spacing: 8) {
                toggle("Mute", on: slot.muted, tint: Palette.danger) {
                    rack.toggleMute(rack.selected)
                }
                toggle("Solo", on: rack.soloed.contains(rack.selected), tint: Palette.accent) {
                    rack.toggleSolo(rack.selected)
                }
                toggle("Reset", on: false, tint: Palette.ink2) {
                    rack.slots[rack.selected].level = 1
                    rack.slots[rack.selected].pan = 0
                    rack.slots[rack.selected].tune = 0
                    onTune()
                }
            }

            if !rack.soloed.isEmpty {
                Text("\(rack.soloed.count) pad\(rack.soloed.count == 1 ? "" : "s") soloed — everything else is silent")
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
        }
    }

    private func knobRow<Control: View>(
        _ title: String, value: String, @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).kerning(1.4)
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Text(value).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink)
            }
            control()
        }
    }

    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.02 { return "centre" }
        return "\(pan < 0 ? "L" : "R")\(Int(abs(pan) * 100))"
    }

    private func toggle(_ label: String, on: Bool, tint: Color, act: @escaping () -> Void)
        -> some View {
        Button(action: act) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Palette.onAccent : Palette.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? tint : Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(on ? tint : Palette.rule, lineWidth: 1))
        }
    }
}
