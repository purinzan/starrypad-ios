import SwiftUI

/// Where the sounds came from.
///
/// Not decoration and not an afterthought: the acoustic kit is CC BY 3.0, and
/// that licence requires attribution wherever the sounds are used. A line in a
/// text file in a repository is not "wherever they are used" - the person
/// playing them has to be able to find it, so it lives in the app.
struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(
                    "Acoustic kit",
                    body: "Salamander Drumkit by Alexander Holm, licensed CC BY 3.0. "
                        + "Trimmed for low latency playback and converted to 16-bit 48 kHz.",
                    link: "creativecommons.org/licenses/by/3.0/"
                )
                section(
                    "808 kit",
                    body: "Roland TR-808 Sound Sample Set by Michael Fischer, as published "
                        + "by the TidalCycles project under CC0 1.0. Trimmed, resampled to "
                        + "48 kHz and normalised.",
                    link: "creativecommons.org/publicdomain/zero/1.0/"
                )
                section(
                    "Glass sounds",
                    body: "Generated for this app rather than recorded: inharmonic partials, "
                        + "a filtered noise transient, and scattered grains for the tail.",
                    link: nil
                )
                section(
                    "Your recordings",
                    body: "Anything you sample stays on this device. Nothing is uploaded, "
                        + "and the app has no account, no analytics and no network access.",
                    link: nil
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground)
    }

    private func section(_ title: String, body: String, link: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).kerning(1.4)
                .foregroundStyle(Palette.accent)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let link {
                Text(link)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
        }
    }
}
