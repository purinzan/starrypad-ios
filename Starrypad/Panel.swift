import SwiftUI
import UIKit

/// The hardware skin, assembled from generated art.
///
/// Every surface here is an image. The only thing the app adds is colour and
/// opacity, and it adds them for a reason: a pad lights up with the bank it is
/// in and the force of the hit, so its glow is one white mask tinted at
/// runtime rather than a sheet of baked variants that could never cover
/// 4 banks x 128 velocities.
enum Panel {

    /// The glow ring sits on the middle 66% of its canvas, measured off the
    /// file: alpha peaks at 16.7% and 83.3% across the centre row. To land the
    /// ring on a pad's own edge, the mask is drawn half again as large.
    static let glowScale: CGFloat = 1.5

    /// Cap insets, in points after the scale below. A frame 42 image pixels
    /// thick would be 42 points of border on a 38 point button, which is why
    /// these are divided down rather than used raw.
    enum Slice {
        static let chiclet = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        static let bezel = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        static let slot = EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
        static let grille = EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
    }

    /// The art was generated at @3x, so it is loaded as @3x. Without this every
    /// image is treated as one pixel to the point and lands three times too
    /// big, taking its 9-slice borders with it.
    static func art(_ name: String, scale: CGFloat = 3) -> Image {
        guard let art = UIImage(named: name), let cg = art.cgImage else {
            return Image(systemName: "square")
        }
        return Image(uiImage: UIImage(cgImage: cg, scale: scale, orientation: .up))
    }
}

/// The chassis behind everything, tiled from one seamless square.
struct PanelGround: View {
    var body: some View {
        Panel.art("panel-tile", scale: 2)
            .resizable(resizingMode: .tile)
            .ignoresSafeArea()
            // The generated tile came back at about 18% grey. Everything meant
            // to sit on it - button faces at 16% - then reads as the same
            // surface, so the chassis is brought down to the near-black the
            // parts were made for. A filter on the art, not a redraw of it.
            .colorMultiply(Color(white: 0.44))
            // The tile is evenly lit by design, so the depth in the real thing -
            // light gathering at the top of the case - is added here rather than
            // baked into a texture that has to repeat.
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.045), .clear, .black.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }
}

/// One rubber pad: the moulded face, and a tinted copy of the glow mask over it.
struct ArtPad: View {
    var hue: Color
    var energy: Double            // 0 at rest, 1 at a full velocity hit
    var dimmed: Bool

    private enum GlowSpec {
        static let perimeterInset: CGFloat = 5
        static let perimeterLineWidth: CGFloat = 2
        static let perimeterRestOpacity = 0.62
        static let perimeterEnergyOpacity = 0.30
        static let firstPassRest = 0.0
        static let firstPassRange = 0.64
        static let secondPassRange = 0.58
        static let shadowRest = 0.0
        static let shadowRange = 0.50
        static let shadowRadiusRest: CGFloat = 0
        static let shadowRadiusRange: CGFloat = 10
        static let cornerRadius: CGFloat = 11
    }

    /// A crisp hue perimeter at rest, then a decisive bloom when played or
    /// selected. The colour should guide you, not fog the whole pad grid.
    private var glowOpacity: Double {
        GlowSpec.firstPassRest + energy * GlowSpec.firstPassRange
    }

    private var perimeterOpacity: Double {
        min(1, GlowSpec.perimeterRestOpacity + energy * GlowSpec.perimeterEnergyOpacity)
    }

    var body: some View {
        ZStack {
            Panel.art("pad-face")
                .resizable()

            RoundedRectangle(cornerRadius: GlowSpec.cornerRadius)
                .strokeBorder(hue.opacity(perimeterOpacity),
                              lineWidth: GlowSpec.perimeterLineWidth)
                .padding(GlowSpec.perimeterInset)

            Panel.art("pad-glow")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(hue)
                // scaleEffect rather than a measured frame: the ring has to
                // overhang the pad, and a GeometryReader here takes whatever
                // space is offered rather than the pad's own, which lands the
                // overlay a whole cell away from the pad it belongs to.
                .scaleEffect(Panel.glowScale)
                .opacity(glowOpacity)
                .blendMode(.plusLighter)
                // A second pass through the same mask. One tinted copy of a
                // soft ring is a wash; laying it over itself gives the diffuser
                // a bright core with the bloom still around it.
            Panel.art("pad-glow")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(hue)
                .scaleEffect(Panel.glowScale * 0.97)
                .opacity(energy * GlowSpec.secondPassRange)
                .blendMode(.plusLighter)
        }
        .compositingGroup()
        .shadow(color: hue.opacity(GlowSpec.shadowRest + energy * GlowSpec.shadowRange),
                radius: GlowSpec.shadowRadiusRest + energy * GlowSpec.shadowRadiusRange)
        .opacity(dimmed ? 0.4 : 1)
    }
}

/// The small square buttons across the panel: one art file lit, one unlit.
struct ArtButton: View {
    var label: String
    var hue: Color
    var on: Bool
    var enabled = true
    var minHeight: CGFloat = 30
    var fontSize: CGFloat = 12

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(on ? .black.opacity(0.85)
                             : enabled ? Color(white: 0.80) : Color(white: 0.36))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                ZStack {
                    Panel.art("chiclet-off")
                        .resizable(capInsets: Panel.Slice.chiclet, resizingMode: .stretch)
                    if on {
                        Panel.art("chiclet-on")
                            .resizable(capInsets: Panel.Slice.chiclet, resizingMode: .stretch)
                            .renderingMode(.template)
                            .foregroundStyle(hue)
                    }
                }
            )
            .shadow(color: on ? hue.opacity(0.5) : .clear, radius: 7)
            .opacity(enabled ? 1 : 0.55)
    }
}

/// A knob: the moulded body, the pointer rotated to the value, and a vertical
/// drag to turn it.
///
/// Up and down rather than a circular gesture, because a real knob is turned
/// between finger and thumb and a phone has one contact point - tracing an arc
/// on glass is a party trick, and every hardware app that tried it went back
/// to dragging.
struct ArtKnob: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var tint: Color
    var caption: String
    var diameter: CGFloat = 46
    var reading: String
    var onCommit: () -> Void = {}
    /// Called as the knob turns, for a value the ear should hear immediately.
    var onChange: (Double) -> Void = { _ in }

    @State private var startValue: Double?

    /// How far the finger travels to cross the whole range. Short enough to
    /// reach the ends without a second grab, long enough to place a value.
    private let travel: CGFloat = 160

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Panel.art("knob-body")
                    .resizable()
                    .frame(width: diameter, height: diameter)

                Panel.art("knob-pointer")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(tint)
                    // The pointer art is empty below its own centre, so the
                    // canvas centre is the pivot and rotation needs no offset.
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-135 + 270 * max(0, min(1, fraction))))
                    .shadow(color: tint.opacity(0.6), radius: 3)
            }
            // A knob is small; the grab area is not.
            .frame(width: diameter + 16, height: diameter + 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let from = startValue ?? value
                        if startValue == nil { startValue = value }
                        let span = range.upperBound - range.lowerBound
                        let delta = Double(-drag.translation.height / travel) * span
                        value = min(range.upperBound, max(range.lowerBound, from + delta))
                        onChange(value)
                    }
                    .onEnded { _ in
                        startValue = nil
                        onCommit()
                    }
            )

            // The caption must not be what decides how wide the knob is.
            // MASTER is wider than the knob it names, and on a narrower phone
            // those extra points came off the end of the transport.
            Text(caption)
                .font(.system(size: 8, weight: .semibold)).kerning(1)
                .foregroundStyle(Color(white: 0.44))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(reading)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.86))
        }
    }
}

/// A milled channel, for the things that read as sunk into the panel.
struct ArtSlot<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                Panel.art("slot")
                    .resizable(capInsets: Panel.Slice.slot, resizingMode: .stretch)
            )
    }
}

/// The recessed screen frame around whatever panel is showing.
struct ArtBezel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Panel.art("bezel")
                    .resizable(capInsets: Panel.Slice.bezel, resizingMode: .stretch)
            )
    }
}

/// Report a view's laid-out height, once and whenever it changes.
///
/// Used for the rows the pad grid has to fit around: a layout that guesses
/// their height is a layout that runs off the bottom of a phone nobody
/// tested on.
extension View {
    func measuredHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { report(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in report(height) }
            }
        )
    }
}
