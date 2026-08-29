import SwiftUI

/// The three things the app cannot say for itself.
///
/// Not a tutorial. Everything else here is discoverable by touching it - what
/// is not is the gestures, because a gesture leaves no mark on the screen to
/// suggest it exists. Three is the number that gets read; a fourth turns the
/// set into something to dismiss.
///
/// Each one shows once, over the thing it describes, and never comes back once
/// that thing has been used.
enum Hint: String, CaseIterable, Identifiable {
    case hold, knob, waveform
    var id: String { rawValue }

    var text: String {
        switch self {
        case .hold:     return "パッドを長押しすると、音色や名前を変えられます。そのままドラッグすれば入れ替え。"
        case .knob:     return "ノブは上下にスワイプして回します。"
        case .waveform: return "波形をドラッグして、鳴らす範囲を決めます。"
        }
    }

    private var key: String { "hint.seen.\(rawValue)" }
    var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    func markSeen() { UserDefaults.standard.set(true, forKey: key) }

    /// The first one still owed, or nil once they have all been shown.
    static var next: Hint? { allCases.first { !$0.seen } }
}

/// A small card pointing at whatever it is about.
struct HintBubble: View {
    let hint: Hint
    /// Where the thing being described is, in screen coordinates.
    let anchor: CGRect
    var onDismiss: () -> Void

    private let width: CGFloat = 250

    var body: some View {
        GeometryReader { screen in
            let frame = screen.frame(in: .global)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                // A hole cut over the thing itself, so the sentence and the
                // control are looked at together rather than in turn.
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .frame(width: anchor.width, height: anchor.height)
                    .position(x: anchor.midX - frame.minX, y: anchor.midY - frame.minY)
                    .allowsHitTesting(false)

                card
                    .frame(width: width)
                    .position(x: cardX(in: screen.size, frame: frame),
                              y: cardY(in: screen.size, frame: frame))
            }
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(index + 1) / \(Hint.allCases.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("わかった", action: onDismiss)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private var index: Int { Hint.allCases.firstIndex(of: hint) ?? 0 }

    private func cardX(in size: CGSize, frame: CGRect) -> CGFloat {
        let wanted = anchor.midX - frame.minX
        return min(max(width / 2 + 12, wanted), size.width - width / 2 - 12)
    }

    /// Under the thing when there is room, over it when there is not.
    private func cardY(in size: CGSize, frame: CGRect) -> CGFloat {
        let height: CGFloat = 104
        let below = anchor.maxY - frame.minY + 14 + height / 2
        return below + height / 2 < size.height
            ? below
            : max(height / 2 + 12, anchor.minY - frame.minY - 14 - height / 2)
    }
}
