import SwiftUI

/// The loop as a strip: bar lines, one tick per recorded hit, a playhead.
///
/// The desktop puts this in the Loop cell and it is the one readout worth the
/// space, because it answers the only question you have while overdubbing -
/// where in the bar am I, and did that last hit land.
struct LoopBar: View {
    @ObservedObject var looper: Looper

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The strip already cost the height; saying nothing with it was
            // the waste. Length, which pass, and where in the bar.
            HStack(spacing: 0) {
                // The label was already in the right place saying the right
                // thing; all it needed was to be worth touching.
                Button { looper.cycleLength() } label: {
                    HStack(spacing: 0) {
                        Text("LOOP ").font(.system(size: 9, weight: .semibold)).kerning(1.1)
                            .foregroundStyle(Palette.ink3)
                        Text("\(looper.bars) bar\(looper.bars == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.rule, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                Spacer()
                // What undo would take off, and how much is stacked up.
                if looper.layers > 0 {
                    Text("LAYERS ").font(.system(size: 9, weight: .semibold)).kerning(1.1)
                        .foregroundStyle(Palette.ink3)
                    Text("\(looper.layers)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.ink2)
                }
                Spacer()
                Text(looper.barBeatText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(looper.state == .countIn ? Palette.danger : Palette.ink)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let total = looper.totalBeats
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.ground)

                    ForEach(1..<max(2, Int(total)), id: \.self) { beat in
                        let downbeat = beat % 4 == 0
                        Rectangle()
                            .fill(downbeat ? Palette.rule : Palette.ruleSoft)
                            .frame(width: 1)
                            .offset(x: width * CGFloat(Double(beat) / total))
                    }
                    // A bar you cannot count is a bar you cannot aim at.
                    ForEach(0..<looper.bars, id: \.self) { bar in
                        Text("\(bar + 1)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.ink3)
                            .offset(x: width * CGFloat(Double(bar * 4) / total) + 3, y: 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }

                    // One canvas, not one view per hit. A busy take is
                    // hundreds of marks, and hundreds of views is a stall of
                    // the same family as the one that took the app down.
                    Canvas { context, size in
                        for event in looper.events where event.beat < total {
                            let height = 6 + 12 * CGFloat(event.velocity) / 127
                            let x = size.width * CGFloat(event.beat / total) - 1
                            let hue = Palette.hueHint(
                                Kit.pads[safe: event.padID]?.hue ?? Palette.ink3)
                            context.fill(
                                Path(roundedRect: CGRect(x: x,
                                                         y: (size.height - height) / 2,
                                                         width: 2, height: height),
                                     cornerRadius: 1),
                                with: .color(hue))
                        }
                    }

                    // One playhead, one kind of motion. The count sweeps the
                    // bar exactly as playing does, so the line never stops or
                    // jumps between states - it just keeps travelling.
                    if looper.state != .idle {
                        let counting = looper.state == .countIn
                        let sweep = looper.sweep
                        if counting {
                            Rectangle()
                                .fill(Palette.danger.opacity(0.18))
                                .frame(width: width * CGFloat(sweep))
                        }
                        Rectangle()
                            .fill(counting || looper.state == .recording
                                  ? Palette.danger : Palette.accent)
                            .frame(width: 2)
                            .offset(x: width * CGFloat(sweep))
                    }

                    if looper.state == .countIn {
                        Text("\(looper.countRemaining)")
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.danger)
                            .shadow(color: .black.opacity(0.9), radius: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.rule, lineWidth: 1))
        }
    }
}

extension Array {
    /// Kit.pads is fixed at sixteen; a stale event should not crash the strip.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
