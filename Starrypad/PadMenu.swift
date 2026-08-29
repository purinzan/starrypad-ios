import SwiftUI

/// The menu a held pad opens, in the shape iOS uses for a held app icon.
///
/// Glass rather than a painted panel: the system's own material is what makes
/// this read as a menu over the instrument rather than another part of it, and
/// it is the one place in the app where borrowing the platform's look is right
/// - a menu is the phone's idiom, not the sampler's.
struct PadMenu: View {
    let slot: PadSlot
    let label: String
    /// Where the held pad sits, so the menu comes out of it rather than from
    /// the middle of the screen.
    let anchor: CGRect

    var onRename: () -> Void
    var onChangeSound: () -> Void
    var onReset: () -> Void
    var onDismiss: () -> Void

    private let width: CGFloat = 232

    var body: some View {
        GeometryReader { screen in
            ZStack(alignment: .topLeading) {
                // The backdrop dims the panel and takes the tap that closes
                // the menu, which is how every menu on the phone behaves.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                card
                    .frame(width: width)
                    .offset(x: x(in: screen.size), y: y(in: screen.size))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(slot.label)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            row("Rename", systemImage: "pencil", action: onRename)
            Divider().padding(.leading, 46)
            row("Change sound", systemImage: "waveform", action: onChangeSound)
            Divider().padding(.leading, 46)
            row("Reset pad", systemImage: "arrow.counterclockwise",
                tint: .red, action: onReset)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }

    private func row(_ title: String, systemImage: String,
                     tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .frame(width: 18)
                Text(title).font(.system(size: 15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placement

    /// Centred on the pad, but never off the edge of the screen.
    private func x(in size: CGSize) -> CGFloat {
        let wanted = anchor.midX - width / 2
        return min(max(12, wanted), size.width - width - 12)
    }

    /// Below the pad when there is room, above it when there is not, so the
    /// menu never covers the pad it belongs to.
    private func y(in size: CGSize) -> CGFloat {
        let height: CGFloat = 226
        let below = anchor.maxY + 10
        return below + height < size.height ? below : max(12, anchor.minY - height - 10)
    }
}
