import SwiftUI

/// The handful of preferences that belong to the player rather than to a pad
/// or to a take.
///
/// These used to be squeezed into the mixer's last row, where they were both
/// cramped and wrong: the mixer is about the pad you have selected, and none
/// of these are. A settings button is the honest place for settings.
struct SettingsView: View {
    @ObservedObject var looper: Looper
    @ObservedObject var force: StrikeForce
    @Binding var velocityFromForce: Bool
    var player: SamplePlayer
    var midiSource: String?
    var layout: String
    var hasLearned: Bool
    var onLearn: () -> Void

    @State private var clickVolume: Double

    init(looper: Looper, force: StrikeForce,
         velocityFromForce: Binding<Bool>, player: SamplePlayer,
         midiSource: String?, layout: String, hasLearned: Bool,
         onLearn: @escaping () -> Void) {
        self.looper = looper
        self.force = force
        self._velocityFromForce = velocityFromForce
        self.player = player
        self.midiSource = midiSource
        self.layout = layout
        self.hasLearned = hasLearned
        self.onLearn = onLearn
        self._clickVolume = State(initialValue: Double(player.clickVolume))
    }

    /// What the app is doing about the controller's layout, in one line.
    ///
    /// Most controllers need nothing: a 4x4 pad grid sends a contiguous block
    /// of notes and the app reads it straight off. Learning exists for the
    /// ones that do not, which is why it lives here rather than beside the
    /// banks - a permanent button for a once-per-controller errand, on a
    /// screen most people use with no controller at all.
    private var layoutNote: String {
        guard midiSource != nil else {
            return "クラスコンプライアントの USB MIDI 機器をつなぐと、ここに名前が出ます。"
        }
        if hasLearned { return "この機器の並びは学習済みです。" }
        return "並びは推定中（\(layout)）。ほとんどの機器はこれで合います。"
            + "パッドの順番が違うときだけ学習してください。"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                group("演奏") {
                    row("叩く強さ",
                        note: force.available
                            ? "加速度センサーで強さを読みます。切ると、パッドのどこを叩いたかで決まります。"
                            : "このデバイスにはセンサーがありません。") {
                        Picker("", selection: $velocityFromForce) {
                            Text("強さ").tag(true)
                            Text("位置").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                        .disabled(!force.available)
                    }
                }

                group("クリック") {
                    row("テイク中も鳴らす",
                        note: "切ると、カウントの4拍だけで止まります。") {
                        Toggle("", isOn: $looper.clickThrough).labelsHidden()
                    }
                    slider("音量", value: $clickVolume) { player.clickVolume = Float($0) }
                }

                group("MIDI コントローラー") {
                    row(midiSource ?? "接続されていません", note: layoutNote) {
                        Button("並びを学習") { onLearn() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(midiSource == nil ? Palette.ink3 : Palette.accent)
                            .disabled(midiSource == nil)
                    }
                }

                group("録音") {
                    row("1小節カウントする",
                        note: "切ると、RECは小節の頭からそのまま始まります。") {
                        Toggle("", isOn: $looper.countsIn).labelsHidden()
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground)
    }

    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).kerning(1.4)
                .foregroundStyle(Palette.accent)
            content()
        }
    }

    private func row<Control: View>(_ title: String, note: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
    }

    private func slider(_ title: String, value: Binding<Double>,
                        onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Slider(value: value, in: 0...1) { editing in
                if !editing { onChange(value.wrappedValue) }
            }
            .tint(Palette.accent)
            .onChange(of: value.wrappedValue) { _, new in onChange(new) }
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
