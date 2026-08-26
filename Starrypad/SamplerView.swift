import SwiftUI

/// Record from the microphone or take the sound out of a video, trim it, and
/// put it on the selected pad.
///
/// The order is deliberate: capture first, then trim, then assign. Assigning
/// is the last step and it is explicit, so nothing lands on a pad you were
/// still playing.
struct SamplerView: View {
    @ObservedObject var rack: Rack
    @ObservedObject var recorder: Recorder
    let player: SamplePlayer

    @Binding var pending: String?          // a captured recording, not yet placed
    @Binding var draft: PadSlot            // the trim being edited
    @Binding var status: String?

    var onAssign: () -> Void
    var onPreview: () -> Void
    var onPreviewSlot: () -> Void
    var onPickVideo: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if pending == nil {
                // A pad already holding a recording opens on its region, so
                // trimming is something you come back to rather than one
                // chance you get while the sample is still warm. The whole
                // file is always there, so an edge can go back out as easily
                // as it came in.
                if case .user = rack.slots[rack.selected].source {
                    TrimView(
                        slot: $rack.slots[rack.selected],
                        peaks: player.peaks(for: rack.slots[rack.selected].source, bins: 320),
                        seconds: player.seconds(of: rack.slots[rack.selected].source),
                        onChange: {
                            let slot = rack.slots[rack.selected]
                            player.invalidate(slot.source)
                            if case .user(let name) = slot.source {
                                Recordings.setTrim(start: slot.start, end: slot.end, for: name)
                            }
                        },
                        onPreview: { onPreviewSlot() }
                    )
                    Divider().overlay(Palette.rule)
                }
                capture
            } else {
                TrimView(
                    slot: $draft,
                    peaks: player.peaks(for: draft.source, bins: 320),
                    seconds: player.seconds(of: draft.source),
                    onChange: { player.invalidate(draft.source) },
                    onPreview: onPreview
                )
                assignRow
            }

            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SAMPLE ONTO \(Banks.label(for: rack.selected))")
                .font(.system(size: 10, weight: .semibold)).kerning(1.4)
                .foregroundStyle(Palette.ink3)

            Button(action: micTapped) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(recorder.isRecording ? Palette.danger : Palette.ink2)
                        .frame(width: 10, height: 10)
                    Text(recorder.isRecording
                         ? String(format: "Stop  ·  %.1f s", recorder.seconds)
                         : "Record from the microphone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                    recorder.isRecording ? Palette.danger : Palette.rule, lineWidth: 1))
            }

            if recorder.isRecording {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.panel2)
                        Capsule()
                            .fill(recorder.level > 0.92 ? Palette.danger : Palette.signal)
                            .frame(width: geometry.size.width * CGFloat(recorder.level))
                    }
                }
                .frame(height: 6)
            }

            Button(action: onPickVideo) {
                HStack(spacing: 10) {
                    Image(systemName: "film").foregroundStyle(Palette.ink2)
                    Text("Take the sound from a video")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.rule, lineWidth: 1))
            }

            Text("The first 30 seconds are taken; trim picks the part that plays.")
                .font(.system(size: 11)).foregroundStyle(Palette.ink3)
        }
    }

    private var assignRow: some View {
        HStack(spacing: 8) {
            Button(action: onPreview) {
                Text("Hear").frame(maxWidth: .infinity)
            }
            .buttonStyle(SamplerButton(tint: Palette.ink2))

            Button(action: onDiscard) {
                Text("Discard").frame(maxWidth: .infinity)
            }
            .buttonStyle(SamplerButton(tint: Palette.ink2))

            Button(action: onAssign) {
                Text("Put on \(Banks.label(for: rack.selected))").frame(maxWidth: .infinity)
            }
            .buttonStyle(SamplerButton(tint: Palette.accent, filled: true))
        }
    }

    private func micTapped() {
        if recorder.isRecording {
            let name = recorder.stop()
            // Hand the output route back straight away: playAndRecord is the
            // quiet one, and nothing should be played through it once the
            // microphone is closed.
            player.endRecordingRoute()
            guard let name else {
                status = "That was too short to keep"
                return
            }
            adopt(name, label: "Mic")
        } else {
            recorder.requestAccess { granted in
                guard granted else {
                    status = "Microphone access is off. Settings › Starrypad › Microphone."
                    return
                }
                player.beginRecordingRoute()
                if !recorder.start() {
                    player.endRecordingRoute()
                    status = "Could not start recording"
                }
            }
        }
    }

    private func adopt(_ name: String, label: String) {
        guard player.load(userSample: name) else {
            status = "Could not read that recording"
            return
        }
        pending = name
        draft = PadSlot(id: rack.selected, source: .user(name: name),
                        label: label, hue: Palette.signal)
        status = nil
    }
}

private struct SamplerButton: ButtonStyle {
    var tint: Color
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Palette.onAccent : Palette.ink)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 7).fill(filled ? tint : Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(filled ? tint : Palette.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
