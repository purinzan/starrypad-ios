import MessageUI
import SwiftUI
import UIKit

/// Writing to the person who made the app, from inside the app.
///
/// Mail rather than a form: a form cannot reply, and the address is the same
/// one the App Store listing and the support page point at, so there is one
/// place to answer from rather than three. Nothing is sent without the draft
/// being read - the compose sheet is the phone's own, and Send is a tap the
/// person takes.
///
/// The address is a plain one with nothing personal in it, because it is
/// printed in the App Store listing, on the support page and inside the app,
/// and an address given to strangers should say nothing about who owns it.
enum Contact {
    static let address = "ryo_2318@icloud.com"

    static var subject: String { "Starrypad \(version) について" }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// What a reply would otherwise have to ask for first. Nothing here
    /// identifies anyone: a version, a model name and an iOS number.
    static func body(midi: String?) -> String {
        """


        ------------------------------
        書きたいことは上に。この行から下は、
        お返事のために消さずに置いていってください。

        Starrypad \(version)
        \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        \(model)
        MIDI: \(midi ?? "接続なし")
        """
    }

    private static var model: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return identifier
    }

    /// Whether the phone can compose mail in place. When it cannot - no mail
    /// account set up - the caller falls back to handing the whole thing to
    /// whatever app does handle mailto.
    static var canComposeInApp: Bool { MFMailComposeViewController.canSendMail() }

    static func mailtoURL(midi: String?) -> URL? {
        var components = URLComponents(string: "mailto:\(address)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(midi: midi)),
        ]
        return components?.url
    }
}

/// The system mail composer, prefilled.
struct MailComposer: UIViewControllerRepresentable {
    let midi: String?
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([Contact.address])
        controller.setSubject(Contact.subject)
        controller.setMessageBody(Contact.body(midi: midi), isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish()
        }
    }
}
