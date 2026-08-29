import SwiftUI

/// Where the sounds came from.
///
/// Not decoration and not an afterthought: the acoustic kit is CC BY 3.0, and
/// that licence requires attribution wherever the sounds are used. A line in a
/// text file in a repository is not "wherever they are used" - the person
/// playing them has to be able to find it, so it lives in the app.
struct CreditsView: View {
    /// What is connected, so a question about a controller arrives with the
    /// controller's name already in it.
    var midiSource: String?

    /// The composer is presented from here rather than from the instrument
    /// behind it. Dismissing one sheet and presenting another a moment later
    /// is a race SwiftUI sometimes loses, and when it loses, the button looks
    /// broken.
    @State private var composing = false
    @State private var note: String?
    /// On by default, because the report is the difference between "音が出ない"
    /// and a cause - but visible, revocable, and readable in full first.
    @State private var attachLog = true
    @State private var showingLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // First, because someone opening this screen with a problem
                // should not have to read three licences to find the way out
                // of it.
                Button(action: contact) {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("問い合わせる")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text("うまく動かないことや、あるといいものについて")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.ink3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $attachLog) {
                        Text("診断ログを添付する")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink2)
                    }
                    .tint(Palette.accent)

                    Button {
                        showingLog.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(showingLog ? "閉じる" : "送る内容を見る")
                            Image(systemName: showingLog ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)

                    if showingLog {
                        ScrollView {
                            Text(Diagnostics.report())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.ink2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 200)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.rule, lineWidth: 1))
                    }
                }

                if let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
        .sheet(isPresented: $composing) {
            MailComposer(midi: midiSource, attachLog: attachLog) { composing = false }
                .ignoresSafeArea()
        }
    }

    /// Compose in place when the phone can. When it cannot - no mail account
    /// set up - hand the whole prefilled message to whatever app does handle
    /// mail, and if even that fails, put the address somewhere it can be
    /// pasted and say so here rather than in a status line on another screen.
    private func contact() {
        note = nil
        if Contact.canComposeInApp {
            composing = true
            return
        }
        guard let url = Contact.mailtoURL(midi: midiSource) else {
            copyAddress()
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened { copyAddress() }
        }
    }

    private func copyAddress() {
        UIPasteboard.general.string = Contact.address
        note = "メールアプリが見つかりませんでした。宛先 \(Contact.address) をコピーしたので、"
            + "お使いのメールアプリから送ってください。"
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
