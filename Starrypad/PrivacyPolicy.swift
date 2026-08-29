import SwiftUI

struct PrivacyPolicyView: View {
    private let webPolicy = URL(string: "https://purinzan.github.io/starrypad-ios/privacy.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("プライバシーポリシー")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.ink)

                Text("最終更新日: 2026年8月29日")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)

                Text("Starrypadは利用者のデータを収集しません。アカウント、広告、解析、追跡機能はなく、録音や設定を外部へ自動送信しません。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)

                policySection("端末内に保存するもの", body:
                    "マイク録音、選択した動画から取り出した音声、パッド配置、音量、パン、チューニング、トリム、名前、テンポ、MIDI設定は、iPhone上のアプリ専用領域に保存されます。アプリを削除すると、これらも削除されます。")

                policySection("マイク", body:
                    "「Record from the microphone」を押したときだけ、iOSの許可を得て録音します。録音中は画面に明確に表示します。バックグラウンドで密かに録音したり、録音内容を送信したりしません。")

                policySection("写真と動画", body:
                    "動画はiOS標準の選択画面から1件だけ選びます。Starrypadが写真ライブラリ全体へアクセスすることはありません。選択した動画の先頭30秒以内の音声だけを端末内で読み取ります。")

                policySection("診断ログ", body:
                    "起動、オーディオ中断、MIDI接続、書き出し結果などの短い診断ログを端末内に保存します。録音内容や入力した名前は記録しません。問い合わせメールに添付する場合も、送信前に内容を確認でき、添付をオフにできます。利用者が送信操作をしない限り外部へ送られません。")

                policySection("第三者提供と追跡", body:
                    "第三者SDK、広告、アクセス解析、クラッシュ収集、トラッキングは使用していません。Starrypadが利用者のデータを第三者へ販売または提供することはありません。")

                policySection("お問い合わせ", body:
                    "本ポリシーについては ryo_2318@icloud.com までお問い合わせください。")

                Link(destination: webPolicy) {
                    Label("Web版を開く", systemImage: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground)
    }

    private func policySection(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Palette.accent)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
