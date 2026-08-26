import SwiftUI

/// Pick the part of a recording that plays, by dragging on the waveform.
///
/// The desktop learned this the hard way: it shipped Crop Start and Crop End as
/// plus and minus buttons stepping 1% at a time, which on a long import is
/// nearly two seconds a tap, while the waveform you could actually drag
/// belonged to a different screen. Dragging is the whole interaction here.
struct TrimView: View {
    @Binding var slot: PadSlot
    let peaks: [Float]
    let seconds: Double
    var onChange: () -> Void
    var onPreview: () -> Void

    @State private var dragEdge: Edge?
    @State private var anchor: Double = 0

    private enum Edge { case start, end, fresh }
    private let grab = 0.05

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REGION").font(.system(size: 10, weight: .semibold)).kerning(1.4)
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Text(String(format: "%.2f s", seconds * (slot.end - slot.start)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Palette.ground)
                    waveform(width: width, height: geometry.size.height)

                    // Everything outside the region is dimmed rather than
                    // marked with a hairline, so the part that sounds reads at
                    // a glance.
                    Rectangle().fill(Palette.ground.opacity(0.7))
                        .frame(width: max(0, width * slot.start))
                    Rectangle().fill(Palette.ground.opacity(0.7))
                        .frame(width: max(0, width * (1 - slot.end)))
                        .offset(x: width * slot.end)

                    handle(at: slot.start, width: width)
                    handle(at: slot.end, width: width)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = clamp(value.location.x / width)
                            if dragEdge == nil { begin(at: ratio) }
                            move(to: ratio)
                        }
                        .onEnded { _ in
                            dragEdge = nil
                            onChange()
                            onPreview()
                        }
                )
            }
            .frame(height: 92)

            Text("Drag to pick the region · drag an edge to move it")
                .font(.system(size: 11)).foregroundStyle(Palette.ink3)
        }
    }

    private func waveform(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let middle = size.height / 2
            let step = size.width / CGFloat(peaks.count)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let x = CGFloat(index) * step
                let half = CGFloat(peak) * (size.height / 2 - 6)
                path.move(to: CGPoint(x: x, y: middle - half))
                path.addLine(to: CGPoint(x: x, y: middle + half))
            }
            context.stroke(path, with: .color(Palette.signal), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }

    private func handle(at ratio: Double, width: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.accent)
            .frame(width: 2)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.accent).frame(width: 10, height: 10)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.accent).frame(width: 10, height: 10)
            }
            .offset(x: width * ratio - 1)
    }

    private func begin(at ratio: Double) {
        if abs(ratio - slot.start) <= grab {
            dragEdge = .start
        } else if abs(ratio - slot.end) <= grab {
            dragEdge = .end
        } else {
            dragEdge = .fresh
            anchor = ratio
        }
    }

    private func move(to ratio: Double) {
        let least = 0.005
        switch dragEdge {
        case .start: slot.start = min(ratio, slot.end - least)
        case .end:   slot.end = max(ratio, slot.start + least)
        case .fresh:
            slot.start = min(anchor, ratio)
            slot.end = max(max(anchor, ratio), slot.start + least)
        case nil: break
        }
        slot.start = clamp(slot.start)
        slot.end = clamp(slot.end)
    }

    private func clamp(_ value: Double) -> Double { max(0, min(1, value)) }
    private func clamp(_ value: CGFloat) -> Double { max(0, min(1, Double(value))) }
}
