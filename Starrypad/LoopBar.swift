import SwiftUI

/// The loop as a strip: bar lines, one tick per recorded hit, a playhead.
///
/// The desktop puts this in the Loop cell and it is the one readout worth the
/// space, because it answers the only question you have while overdubbing -
/// where in the bar am I, and did that last hit land.
struct LoopBar: View {
    @ObservedObject var looper: Looper

    var body: some View {
        // No TimelineView: the looper publishes the sweep, so the bar redraws
        // because the value changed rather than because SwiftUI felt like it.
        Group {
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

                    ForEach(looper.events) { event in
                        Capsule()
                            .fill(Palette.hueHint(Kit.pads[safe: event.padID]?.hue ?? Palette.ink3))
                            .frame(width: 2, height: 6 + 12 * CGFloat(event.velocity) / 127)
                            .offset(x: width * CGFloat(event.beat / total) - 1)
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
        }
        .frame(height: 34)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.rule, lineWidth: 1))
    }
}

extension Array {
    /// Kit.pads is fixed at sixteen; a stale event should not crash the strip.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
