import OSLog
import SwiftUI

struct ContentView: View {
    private static let log = Logger(subsystem: "com.purinzan.starrypad", category: "App")

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var midi = MIDIInput()
    @StateObject private var looper = Looper()
    @StateObject private var rack = Rack()
    @StateObject private var recorder = Recorder()
    @State private var player = SamplePlayer()

    @State private var lit: [Int: Double] = [:]          // slot -> energy
    @State private var velocityFloor = 1
    @State private var lastVelocity = 0
    /// The last few hits, so a preview can be as loud as playing actually is.
    @State private var recentHits: [Int] = []
    @State private var loaded = 0
    @State private var notes = NoteMap()
    @State private var lastNote: UInt8?

    @State private var panel: Panel?
    @State private var pendingSample: String?
    @State private var draft = PadSlot(id: 0, source: .builtIn(file: ""), label: "", hue: .clear)
    @State private var status: String?
    @State private var pickingVideo = false
    @AppStorage("master.decibels")
    private var master = Double(SamplePlayer.defaultMakeupDecibels)
    @State private var learning = false
    /// Every finger currently down, keyed by touch.
    @State private var presses: [Int: Press] = [:]
    /// Holding a pad. Lift without moving and the sound picker opens; drag to
    /// another pad and the two swap. One gesture, decided by what you do next.
    @State private var held: Int?
    @State private var swapTarget: Int?
    @State private var gridSize: CGSize = .zero
    @State private var gridOrigin: CGPoint = .zero
    @State private var picking: Int?
    /// The pad whose menu is open, and where on screen it sits.
    @State private var menuFor: Int?
    @State private var menuAnchor: CGRect = .zero
    /// The pad a reset has been asked for but not yet confirmed.
    @State private var resetting: Int?
    /// The hint currently owed, and where the thing it describes sits.
    @State private var hint: Hint?
    @State private var hintAnchor: CGRect = .zero
    @State private var deckFrame: CGRect = .zero
    /// The chrome the grid has to fit around, measured as it is laid out.
    /// The starting values are what it comes to on a current phone, so the
    /// first frame is already about right rather than visibly settling.
    @State private var chromeAbove: CGFloat = 96
    @State private var chromeBelow: CGFloat = 148
    /// A pad lifted off the grid and following the finger, as on the home
    /// screen: the menu opens on the hold, and dragging out of it picks the
    /// pad up instead.
    @State private var carrying: Int?
    @State private var carryPoint: CGPoint = .zero
    @State private var dropping = false
    @State private var carryOrigin: CGPoint = .zero
    @State private var escaped = false
    @State private var recordings: [String] = []

    @State private var renaming = false
    /// The bank whose name is being edited, and the text so far.
    @State private var renamingBank: Int?
    @State private var showingCredits = false
    @State private var bankDraft = ""
    @State private var taps: [TimeInterval] = []
    @StateObject private var force = StrikeForce()
    @AppStorage("velocityFromForce") private var velocityFromForce = true

    private let holdSeconds = 0.45

    /// The panels are summoned, not resident. There is no "Pads" screen to
    /// go back to, because the pads never went anywhere.
    enum Panel: String, Identifiable, CaseIterable {
        case mixer = "Mixer", sampler = "Sampler"
        var id: String { rawValue }
    }

    /// Production layout tokens for the main performance surface.
    private enum PerformanceSpec {
        static let outerMargin: CGFloat = 16
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 8
        static let sectionGap: CGFloat = 8
        static let padGap: CGFloat = 8
        static let gridInset: CGFloat = 4
        /// What a panel needs to show itself without scrolling. The pads are
        /// allowed to give this much up on a screen too short for both, and
        /// not a point more - and because it is a constant, they give it up
        /// whether or not a panel is open, so nothing moves when one is.
        static let panelRoom: CGFloat = 268
        static let hairline: CGFloat = 1
        static let panelButtonHeight: CGFloat = 46
        static let bankHeight: CGFloat = 40
        static let bankRadius: CGFloat = 8
        static let bankIndicatorHeight: CGFloat = 2
        static let learnWidth: CGFloat = 72
        static let midiDot: CGFloat = 8
        static let knobDiameter: CGFloat = 44
        static let deckDividerHeight: CGFloat = 56
        static let primaryTransportHeight: CGFloat = 56
        static let utilityTransportHeight: CGFloat = 56
        static let transportGap: CGFloat = 8
        static let padCornerRadius: CGFloat = 11
        static let padStroke: CGFloat = 2
        static let selectedPadStroke: CGFloat = 3
        static let pressedShadowBase: CGFloat = 3
        static let pressedShadowRange: CGFloat = 12
    }

    /// Pad 0 is bottom left, so the grid is drawn from the top row down.
    private var rows: [[PadSlot]] {
        let visible = rack.visible
        return stride(from: 12, through: 0, by: -4).map { Array(visible[$0..<($0 + 4)]) }
    }

    private var instrument: some View {
        GeometryReader { screen in
            performance(in: screen.size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelGround())
        .preferredColorScheme(.dark)
        .onAppear(perform: begin)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                // Leaving is the last chance to write anything still pending.
                rack.saveNow()
                return
            }
            player.activateSession(reason: "scene active")
        }
    }

    /// Everything that plays: chrome, banks, the grid, and whatever occupies
    /// the strip beneath it.
    /// The square the pads get, on this screen.
    ///
    /// As wide as the screen allows, unless the screen is not tall enough for
    /// that - on a shorter phone the square gives way rather than pushing the
    /// transport off the bottom. The chrome above and below is measured rather
    /// than assumed, because a hand-kept constant is wrong the first time a
    /// row changes height, and it is the bottom of the screen that pays.
    private func padSide(in size: CGSize) -> CGFloat {
        let width = size.width - PerformanceSpec.outerMargin * 2
        // Four gaps between the five things stacked here, and the small fixed
        // step between the banks and the grid.
        let between = PerformanceSpec.sectionGap * 4 + PerformanceSpec.gridInset
        let fixed = size.height - PerformanceSpec.topInset - PerformanceSpec.bottomInset
            - between - chromeAbove
        return max(180, min(width, fixed - chromeBelow, fixed - PerformanceSpec.panelRoom))
    }

    private func performance(in size: CGSize) -> some View {
        let side = padSide(in: size)
        return VStack(spacing: PerformanceSpec.sectionGap) {
            VStack(spacing: PerformanceSpec.sectionGap) {
                header
                bankRow
                if learning { learnBanner }
            }
            .measuredHeight { chromeAbove = $0 }

            // Sized to the screen and sitting at a fixed distance from the
            // bank row. Opening a panel must not move a single pad - the whole
            // point of leaving them playable is that your hand already knows
            // where they are. All the give is below.
            Spacer(minLength: 0).frame(height: PerformanceSpec.gridInset)
            padGrid.frame(width: side, height: side)
            Spacer(minLength: 0)

            // A panel replaces the loop bar and the transport, and nothing
            // else. The pads stay where they are and stay playable - the
            // point of opening the mixer is usually to hear what you changed.
            if let panel {
                ArtBezel {
                    ScrollView(.vertical, showsIndicators: false) {
                        panelBody(panel)
                    }
                }
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: PerformanceSpec.sectionGap) {
                    ArtSlot(height: 62) { LoopBar(looper: looper) }
                    deck(width: size.width - PerformanceSpec.outerMargin * 2)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onAppear { deckFrame = proxy.frame(in: .global) }
                            }
                        )
                }
                // Only while it is on screen: with a panel open this keeps the
                // last closed measurement, so the grid stays put.
                .measuredHeight { chromeBelow = $0 }
            }
        }
        .padding(.horizontal, PerformanceSpec.outerMargin)
        .padding(.top, PerformanceSpec.topInset)
        .padding(.bottom, PerformanceSpec.bottomInset)
        // Pinned to the screen's own width. A row that wants more than this
        // has to compress, not push the whole instrument off the edge.
        .frame(width: size.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The instrument, and the layers that sit over it: a carried pad, its
    /// menu, the hints, and every sheet and alert the panels open.
    var body: some View {
        instrument
        .overlay {
            GeometryReader { proxy in
                if let carrying {
                    let frame = proxy.frame(in: .global)
                    carriedPad(carrying)
                        .position(x: carryPoint.x - frame.minX,
                                  y: carryPoint.y - frame.minY)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay { if let menuFor { padMenu(for: menuFor) } }
        .overlay {
            if let hint {
                HintBubble(hint: hint, anchor: hintAnchor) {
                    hint.markSeen()
                    withAnimation(.easeOut(duration: 0.18)) { self.hint = nil }
                    // One at a time, and only after the last was acknowledged.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { offerHint() }
                }
            }
        }
        .sheet(item: pickingBinding) { target in soundPicker(for: target.id) }
        .sheet(isPresented: $pickingVideo) { videoPicker }
        .sheet(isPresented: $showingCredits) {
            CreditsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // The only thing in the app that asks. Everything else is undoable,
        // and asking about undoable things is how people learn to dismiss
        // dialogs without reading them.
        .confirmationDialog(
            resetting.map { "Reset \(Banks.label(for: $0))?" } ?? "",
            isPresented: Binding(get: { resetting != nil },
                                 set: { if !$0 { resetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Reset the pad", role: .destructive) {
                guard let slotID = resetting else { return }
                rack.reset(slotID)
                player.invalidate(rack.slots[slotID].source)
                status = "\(Banks.label(for: slotID)) reset"
                resetting = nil
            }
            Button("Cancel", role: .cancel) { resetting = nil }
        } message: {
            Text("The sound, level, pan, tune, trim and name all go back to how the app shipped.")
        }
        .alert("Rename bank", isPresented: Binding(
            get: { renamingBank != nil },
            set: { if !$0 { renamingBank = nil } }
        )) {
            TextField("Name", text: $bankDraft)
            Button("Save") {
                if let index = renamingBank { rack.renameBank(index, to: bankDraft) }
                renamingBank = nil
            }
            Button("Cancel", role: .cancel) { renamingBank = nil }
        }
    }

    private var padGrid: some View {
        GeometryReader { grid in
            VStack(spacing: PerformanceSpec.padGap) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: PerformanceSpec.padGap) {
                        ForEach(rows[row]) { slot in padView(slot) }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(width: grid.size.width, height: grid.size.width)
            .onAppear {
                gridSize = grid.size
                gridOrigin = grid.frame(in: .global).origin
            }
            .onChange(of: grid.size) { _, size in
                gridSize = size
                gridOrigin = grid.frame(in: .global).origin
            }
            .overlay(
                PadTouches(onDown: touchDown, onMove: touchMoved, onUp: touchUp)
            )
        }
        // Square, which fixes the height at whatever the width is - 374 points
        // on this phone, gaps included. Demanding squares is what stops the
        // pads being the thing that gets shaved whenever anything else is
        // added: there is nothing left to negotiate away.
        .aspectRatio(1, contentMode: .fit)
    }

    /// The pad under the finger, drawn above everything and following it.
    private func carriedPad(_ slotID: Int) -> some View {
        let cell = cellFrame(for: slotID)
        let slot = rack.slots[slotID]
        return ZStack {
            ArtPad(hue: slot.hue, energy: 0.55, dimmed: false)
            Text(slot.label.uppercased())
                .font(.system(size: 11, weight: .semibold)).kerning(0.8)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7).lineLimit(2)
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(.horizontal, 6)
        }
        .frame(width: cell.width, height: cell.height)
        .scaleEffect(dropping ? 1.0 : 1.12)
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    private func padMenu(for slotID: Int) -> some View {
        PadMenu(
            slot: rack.slots[slotID],
            label: Banks.label(for: slotID),
            anchor: menuAnchor,
            onRename: {
                closeMenu()
                rack.selected = slotID
                panel = .mixer
                renaming = true
            },
            onChangeSound: {
                closeMenu()
                recordings = Recordings.all()
                picking = slotID
            },
            onReset: {
                closeMenu()
                resetting = slotID
            },
            onDismiss: closeMenu
        )
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.16)) {
            menuFor = nil
            carrying = nil
        }
        held = nil
        escaped = false
    }

    private var pickingBinding: Binding<PadTarget?> {
        Binding(get: { picking.map { PadTarget(id: $0) } }, set: { picking = $0?.id })
    }

    private func soundPicker(for target: Int) -> some View {
        SoundPicker(
            target: target,
            recordings: recordings,
            onPick: { source, label in
                if case .user(let name) = source { _ = player.load(userSample: name) }
                rack.setSound(source, label: label, on: target)
                status = "\(label) is on \(Banks.label(for: target))"
            },
            onPreview: { source in
                if case .user(let name) = source { _ = player.load(userSample: name) }
                // Heard as it is, not as the pad has it set: this is choosing a
                // sound, and the pad's tune and trim belong to the old one.
                var bare = PadSlot(id: target, source: source, label: "", hue: .clear)
                bare.level = 1
                audition(bare)
            },
            onDelete: { name in
                try? FileManager.default.removeItem(at: Recordings.url(for: name))
                Recordings.forget(name)
                recordings = Recordings.all()
            }
        )
    }

    private var videoPicker: some View {
        VideoPicker(
            read: { url in
                DispatchQueue.main.async {
                    pickingVideo = false
                    status = "Reading the video…"
                }
                let result = VideoImport.extractAudioBlocking(from: url)
                DispatchQueue.main.async { finishVideoImport(result) }
            },
            onCancel: { pickingVideo = false }
        )
        .ignoresSafeArea()
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: PerformanceSpec.sectionGap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(midi.sourceNames.isEmpty ? Palette.ink3 : Palette.signal)
                    .frame(width: PerformanceSpec.midiDot, height: PerformanceSpec.midiDot)
                Text("MIDI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(midi.sourceNames.first ?? "Not connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(midi.sourceNames.isEmpty ? Palette.ink3 : Palette.ink2)
                    .lineLimit(1)
                if let lastNote {
                    Text("\(lastNote)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .padding(.leading, 2)
                }
                Spacer(minLength: 0)
                // Where the sounds came from. The acoustic kit's licence
                // requires the credit to travel with the sounds.
                Button { showingCredits = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.ink3)
                }
                .accessibilityLabel("Credits and licences")
            }

            HStack(spacing: 10) {
                // Modes, not destinations: pressing one opens a panel over the
                // instrument and closing it puts you back where you were playing.
                ForEach(Panel.allCases) { which in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            panel = panel == which ? nil : which
                        }
                    } label: {
                        PerformancePanelButton(panel: which, on: panel == which)
                    }
                }
            }
        }
    }

    private func readout(_ caption: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption.uppercased()).font(.system(size: 9, weight: .semibold)).kerning(1.4)
                .foregroundStyle(Palette.ink3)
            Text(value).font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(accent ? Palette.accent : Palette.ink)
                .lineLimit(1)
        }
        .frame(minWidth: 56, alignment: .leading)
    }

    private var bankRow: some View {
        HStack(spacing: PerformanceSpec.sectionGap) {
            HStack(spacing: 0) {
                ForEach(0..<Banks.count, id: \.self) { index in
                    Button { rack.selectBank(index) } label: {
                        BankSegment(index: index, title: rack.bankTitles[index],
                                    selected: index == rack.bank)
                    }
                    // Hold to rename, the same gesture that renames a pad.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            bankDraft = rack.bankTitles[index]
                            renamingBank = index
                        }
                    )
                    if index < Banks.count - 1 {
                        Rectangle().fill(Palette.rule.opacity(0.75)).frame(width: 1)
                    }
                }
            }
            .frame(height: PerformanceSpec.bankHeight)
            .background(
                RoundedRectangle(cornerRadius: PerformanceSpec.bankRadius)
                    .fill(
                        LinearGradient(
                            colors: [Palette.panel2.opacity(0.78),
                                     Palette.ground.opacity(0.92)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: PerformanceSpec.bankRadius)
                    .strokeBorder(Palette.rule.opacity(0.9), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PerformanceSpec.bankRadius))

            Button {
                if learning {
                    notes.cancelLearning()
                    learning = false
                    status = nil
                } else {
                    notes.beginLearning()
                    learning = true
                }
            } label: {
                ArtButton(label: learning ? "Cancel" : "Learn",
                          hue: Palette.danger, on: learning,
                          minHeight: PerformanceSpec.bankHeight - 4)
                    .frame(width: PerformanceSpec.learnWidth)
            }
        }
    }

    private struct BankSegment: View {
        let index: Int
        let title: String
        let selected: Bool

        var body: some View {
            Text("\(Banks.names[index]) \(title)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Palette.accent : Palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: PerformanceSpec.bankHeight)
                .background(
                    LinearGradient(
                        colors: selected
                        ? [Palette.accentSoft.opacity(0.95), Palette.panel.opacity(0.25)]
                        : [.white.opacity(0.025), .black.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? Palette.accent : .clear)
                        .frame(height: PerformanceSpec.bankIndicatorHeight)
                        .padding(.horizontal, 8)
                }
        }
    }

    private struct PerformancePanelButton: View {
        let panel: Panel
        let on: Bool

        var body: some View {
            // The icon travels with the word as one centred group. Pinned to
            // the leading edge it made the label read as off-centre, which on
            // a pair of buttons side by side is the first thing you notice.
            ArtButton(label: "", hue: Palette.accent, on: on,
                      minHeight: PerformanceSpec.panelButtonHeight)
                .overlay {
                    HStack(spacing: 8) {
                        Image(systemName: panel == .mixer ? "slider.horizontal.3" : "waveform")
                            .font(.system(size: 16, weight: .semibold))
                        Text(panel.rawValue)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(on ? .black.opacity(0.85) : Color(white: 0.80))
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 2)
        }
    }

    /// While learning, the grid asks for one pad at a time and the rest go
    /// quiet, so there is never a question about which one it means.
    private var learnBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.danger).frame(width: 8, height: 8)
            Text("Hit the pad shown in orange on your controller")
                .font(.system(size: 12)).foregroundStyle(Palette.ink)
            Spacer()
            if let position = notes.learningPosition {
                Text("\(position + 1) / \(Banks.padCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.danger, lineWidth: 1))
    }

    @ViewBuilder
    private func panelBody(_ which: Panel) -> some View {
        switch which {
        case .mixer:
            MixerView(rack: rack, looper: looper, renaming: $renaming,
                      velocityFromForce: $velocityFromForce, force: force,
                      onTune: { player.invalidate(rack.slots[rack.selected].source) },
                      onAudition: { audition(rack.slots[rack.selected]) })
        case .sampler:
            samplerPanel
        }
    }

    private var samplerPanel: some View {
        SamplerView(
                rack: rack, recorder: recorder, player: player,
                pending: $pendingSample, draft: $draft, status: $status,
                onAssign: assignPending,
                onPreview: { audition(draft) },
                onPreviewSlot: { audition(rack.slots[rack.selected]) },
                onPickVideo: { pickingVideo = true },
                onDiscard: { pendingSample = nil; status = nil }
        )
    }

    /// Tempo and master beside the transport, which is where they sit on the
    /// machine this borrows from - and which costs one row instead of two.
    /// Tempo and master beside the transport, sized to whatever width the
    /// phone has. Fixed button widths fitted one screen and ran off the next.
    private func deck(width: CGFloat) -> some View {
        let knob = PerformanceSpec.knobDiameter + 16
        let divider = PerformanceSpec.hairline + 8
        let gaps = PerformanceSpec.transportGap * 6
        let free = max(160, width - knob * 2 - divider - gaps)
        // Rec and Play are the ones found without looking; they get the room.
        let unit = free / 4.6
        return HStack(alignment: .center, spacing: PerformanceSpec.transportGap) {
            ArtKnob(value: $looper.bpm, range: 40...240, tint: Palette.accent,
                    caption: "TEMPO", diameter: PerformanceSpec.knobDiameter,
                    reading: "\(Int(looper.bpm))")
                .frame(width: knob)
            ArtKnob(value: $master, range: 0...12, tint: Palette.danger,
                    caption: "MASTER", diameter: PerformanceSpec.knobDiameter,
                    reading: String(format: "%+.0f", master),
                    onCommit: { player.makeupDecibels = Float(master) })
                .frame(width: knob)
            Rectangle()
                .fill(Palette.rule)
                .frame(width: PerformanceSpec.hairline,
                       height: PerformanceSpec.deckDividerHeight)
                .padding(.horizontal, 4)
            Spacer(minLength: 0)
            transport(primary: unit * 1.3, utility: unit)
        }
    }

    private func transport(primary: CGFloat, utility: CGFloat) -> some View {
        HStack(spacing: PerformanceSpec.transportGap) {
            transportButton(
                looper.state == .countIn ? "\(looper.countRemaining)"
                : looper.armed ? "Cue" : "Rec",
                tint: Palette.danger,
                on: looper.state == .recording || looper.state == .countIn || looper.armed,
                minHeight: PerformanceSpec.primaryTransportHeight,
                width: primary,
                fontSize: 20
            ) {
                looper.toggleRecord()
            }
            transportButton("Play", tint: Palette.accent, on: looper.state == .playing,
                            minHeight: PerformanceSpec.primaryTransportHeight,
                            width: primary,
                            fontSize: 20) {
                looper.togglePlay()
            }
            // Same height as Rec and Play, because a ragged row of three
            // button sizes reads as an accident. Width is what says these two
            // matter less, and the tint says it again.
            transportButton("Undo", tint: Palette.ink2, on: false,
                            enabled: looper.canUndo || rack.canUndo,
                            minHeight: PerformanceSpec.utilityTransportHeight,
                            width: utility,
                            fontSize: 11) {
                // The loop first: while you are playing into it, that is what
                // "undo" means. Pad edits come back once there is nothing left
                // to peel off the take.
                if looper.canUndo { looper.undo() } else { rack.undoEdit() }
            }
            transportButton("Clear", tint: Palette.ink2, on: false,
                            enabled: !looper.events.isEmpty,
                            minHeight: PerformanceSpec.utilityTransportHeight,
                            width: utility,
                            fontSize: 11) {
                looper.clear()
            }
        }
    }

    private func transportButton(
        _ label: String, tint: Color, on: Bool, enabled: Bool = true,
        minHeight: CGFloat = 38, width: CGFloat? = nil, fontSize: CGFloat = 12,
        act: @escaping () -> Void
    ) -> some View {
        Button(action: act) {
            ArtButton(label: label, hue: tint, on: on, enabled: enabled,
                      minHeight: minHeight, fontSize: fontSize)
                .frame(width: width)
        }
        .disabled(!enabled)
    }

    // MARK: - Pads

    private func padView(_ slot: PadSlot) -> some View {
        let energy = lit[slot.id] ?? 0
        let wanted = learning && notes.learningPosition == slot.positionInBank
        let isHeld = held == slot.id
        let isSwapTarget = held != nil && swapTarget == slot.id && held != slot.id
        let isSelected = wanted || rack.selected == slot.id
        let sounding = energy > 0
        let silent = slot.muted || (!rack.soloed.isEmpty && !rack.soloed.contains(slot.id))
        return GeometryReader { geometry in
            ZStack {
                ArtPad(hue: slot.hue, energy: energy, dimmed: learning && !wanted)
                VStack(spacing: 3) {
                    Text(slot.label.uppercased())
                        .font(.system(size: 12, weight: .bold)).kerning(0.6)
                        .foregroundStyle(sounding ? .white
                                         : isSelected ? Palette.ink : Palette.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .shadow(color: .black.opacity(0.9), radius: 2)
                    if case .user = slot.source {
                        Text("SAMPLE").font(.system(size: 8, weight: .semibold)).kerning(1)
                            .foregroundStyle(Palette.signal)
                    }
                }
                .padding(.horizontal, 6)
            }
            .opacity(silent ? 0.5 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: PerformanceSpec.padCornerRadius)
                    .strokeBorder(
                        isSwapTarget ? Palette.signal
                        : isHeld ? Palette.danger
                        : isSelected ? Palette.accent : .clear,
                        lineWidth: isSelected ? PerformanceSpec.selectedPadStroke
                        : PerformanceSpec.padStroke)
                    .padding(2)
            )
            .scaleEffect(isHeld ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHeld)
            .shadow(color: Palette.accent.opacity(energy * 0.55),
                    radius: PerformanceSpec.pressedShadowBase
                    + PerformanceSpec.pressedShadowRange * energy)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Wiring

    private func begin() {
        loaded = player.preload(Kit.all)
        // Pads restored from the last session point at recordings that are not
        // loaded yet, and a pad that makes no sound is a pad you think is
        // broken.
        for slot in rack.slots {
            if case .user(let name) = slot.source { _ = player.load(userSample: name) }
        }
        // Kept even though it is no longer on screen: it is the number that
        // decides whether this feels like an instrument, and it belongs in the
        // log when someone says the app feels slow.
        Self.log.info("output latency \(player.outputLatencyMilliseconds, format: .fixed(precision: 2)) ms")
        player.activateSession(reason: "launch")
        player.start()
        player.makeupDecibels = Float(master)
        looper.onClick = { accent in player.click(accent: accent) }
        looper.onFire = { slotID, velocity in
            guard rack.slots.indices.contains(slotID) else { return }
            strike(rack.slots[slotID], velocity: velocity, record: false)
        }
        midi.onNote = { note, velocity in
            // Never drop a hit: NoteMap always answers with a pad.
            let position = notes.position(for: note)
            let slotID = rack.bank * Banks.padCount + position
            lastNote = note
            rack.selected = slotID
            strike(rack.slots[slotID], velocity: Int(velocity))
            if notes.learningPosition == nil, learning {
                learning = false
                status = "Layout learned"
            }
        }
        midi.start()
        force.start()
        // After the first frame, so the anchors are real rather than zero.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { offerHint() }
    }

    /// Show the next hint that is still owed, pointed at its own control.
    private func offerHint() {
        guard hint == nil, let next = Hint.next else { return }
        switch next {
        case .hold:
            guard gridSize.width > 0 else { return }
            hintAnchor = cellFrame(for: rack.bank * Banks.padCount + 5)
        case .knob:
            guard deckFrame.width > 0 else { return }
            hintAnchor = CGRect(x: deckFrame.minX, y: deckFrame.minY,
                                width: 110, height: deckFrame.height)
        case .waveform:
            // Only worth saying once there is a waveform to drag.
            guard panel == .sampler else { return }
            hintAnchor = .zero
        }
        withAnimation(.easeOut(duration: 0.22)) { hint = next }
    }

    /// One finger's worth of press, so two fingers do not share one set of
    /// variables and cancel each other's hold.
    private struct Press {
        var slot: Int
        var origin: Int          // the position it landed on
        var point: CGPoint       // where the finger is, in the grid's space
        var dragged = false
        var target: Int?
    }

    /// How far the finger must travel to pull a held pad out of its menu.
    ///
    /// Matched to the home screen: a held icon resists a little, and only
    /// commits to being carried once you clearly mean it. Without the
    /// resistance the smallest wobble tears the menu away from under you.
    private static let escapeDistance: CGFloat = 26

    /// The classic rubber band: full movement at zero, asymptotically none.
    /// The pad leans towards the finger without leaving home.
    private static func resisted(_ delta: CGFloat) -> CGFloat {
        let pull = Self.escapeDistance
        return (1 - 1 / (abs(delta) / pull + 1)) * pull * (delta < 0 ? -1 : 1)
    }

    private func touchDown(id: Int, position: Int, depth: Double, point: CGPoint) {
        let slotID = rack.bank * Banks.padCount + position
        presses[id] = Press(slot: slotID, origin: position, point: point)
        rack.selected = slotID

        let byPosition = 24 + Int(depth * 103)
        let velocity = velocityFromForce ? (force.velocity() ?? byPosition) : byPosition
        strike(rack.slots[slotID], velocity: velocity)

        // Holding is a one finger gesture. With a second finger down you are
        // playing, and nothing should open a sheet under your hands.
        guard presses.count == 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            guard presses.count == 1, let press = presses[id],
                  !press.dragged, held == nil else { return }
            held = press.slot
            swapTarget = nil
            escaped = false
            carryOrigin = press.point
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            menuAnchor = cellFrame(for: press.slot)
            // The pad lifts with the menu, not when you start moving: on the
            // home screen the icon is already off the surface while you read
            // the menu, which is what tells you it can be moved.
            carryPoint = CGRect.center(of: cellFrame(for: press.slot))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                carrying = press.slot
                menuFor = press.slot
            }
        }
    }

    private func touchMoved(id: Int, position: Int?, point: CGPoint) {
        guard var press = presses[id] else { return }
        press.point = point
        press.target = position.map { rack.bank * Banks.padCount + $0 }
        defer { presses[id] = press }

        guard held == press.slot else {
            if let position, position != press.origin { press.dragged = true }
            return
        }

        let delta = CGPoint(x: point.x - carryOrigin.x, y: point.y - carryOrigin.y)
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)

        if !escaped {
            guard distance > Self.escapeDistance else {
                // Still in the menu's grip: the pad leans towards the finger
                // and springs back rather than following it.
                let home = CGRect.center(of: cellFrame(for: press.slot))
                carryPoint = CGPoint(x: home.x + Self.resisted(delta.x),
                                     y: home.y + Self.resisted(delta.y))
                return
            }
            // Pulled free. The menu goes, and from here the pad is simply
            // wherever the finger is.
            escaped = true
            press.dragged = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.14)) { menuFor = nil }
        }

        press.dragged = true
        carryPoint = CGPoint(x: gridOrigin.x + point.x, y: gridOrigin.y + point.y)
        if let position { swapTarget = rack.bank * Banks.padCount + position }
    }

    private func touchUp(id: Int) {
        guard let press = presses.removeValue(forKey: id) else { return }
        guard held == press.slot else { return }
        held = nil
        // A hold that never escaped is a menu, and the menu is already open;
        // the pad stays lifted under it until something closes it.
        guard escaped else { swapTarget = nil; return }

        let source = press.slot
        let target = swapTarget
        // Drop it: the carried pad flies to wherever it landed and the swap
        // happens under it, so the movement is the thing you see rather than
        // two labels changing places.
        if let target, target != source {
            carryPoint = CGRect.center(of: cellFrame(for: target))
            rack.swap(source, target)
            looper.swapPads(source, target)
            player.invalidate(rack.slots[source].source)
            player.invalidate(rack.slots[target].source)
            status = "\(Banks.label(for: source)) and \(Banks.label(for: target)) swapped"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // Anywhere that is not another pad - the transport, the knobs, off
            // the grid entirely - is not a destination, so it goes home.
            carryPoint = CGRect.center(of: cellFrame(for: source))
        }
        dropping = true
        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) { dropping = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            carrying = nil
            swapTarget = nil
            escaped = false
        }
    }

    /// Where a slot's pad sits on screen, so its menu can come out of it.
    private func cellFrame(for slotID: Int) -> CGRect {
        let position = slotID % Banks.padCount
        let column = CGFloat(position % 4), row = CGFloat(3 - position / 4)
        let cell = CGSize(width: gridSize.width / 4, height: gridSize.height / 4)
        return CGRect(x: gridOrigin.x + column * cell.width,
                      y: gridOrigin.y + row * cell.height,
                      width: cell.width, height: cell.height)
    }

    private func strike(_ slot: PadSlot, velocity: Int, record: Bool = true) {
        let expanded = Velocity.expand(velocity, floor: velocityFloor)
        if rack.audible(slot.id) {
            player.play(slot, velocity: expanded)
        }
        lastVelocity = expanded
        recentHits.append(expanded)
        if recentHits.count > 8 { recentHits.removeFirst() }
        if record { looper.capture(padID: slot.id, velocity: expanded) }

        let energy = Double(expanded) / 127.0
        lit[slot.id] = energy
        let hold = 0.075 + 0.11 * energy
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(.easeOut(duration: 0.12)) { lit[slot.id] = 0 }
        }
    }

    /// Hear a pad the way it sounds when you play it.
    ///
    /// A preview used to be sent at 110, which is nearly the top of the curve:
    /// you checked a sample at close to full force, assigned it, and then it
    /// was quieter every time you actually hit the pad. The average of the
    /// last few real hits is what playing sounds like, so that is what a
    /// preview is worth - and until anything has been hit, a middling 100.
    private var auditionVelocity: Int {
        guard !recentHits.isEmpty else { return 100 }
        return recentHits.reduce(0, +) / recentHits.count
    }

    private func audition(_ slot: PadSlot) {
        player.audition(slot, velocity: auditionVelocity)
    }

    private func assignPending() {
        guard let name = pendingSample else { return }
        let target = rack.selected
        rack.assign(name, label: draft.label,
                    start: draft.start, end: draft.end, to: target)
        pendingSample = nil
        status = "\(draft.label) is on \(Banks.label(for: target))"
        panel = nil
    }

    private func finishVideoImport(_ result: Result<String, Error>) {
        switch result {
        case .failure(let error):
            status = error.localizedDescription
        case .success(let name):
            guard player.load(userSample: name) else {
                status = "Could not read that recording"
                return
            }
            pendingSample = name
            draft = PadSlot(id: rack.selected, source: .user(name: name),
                            label: "Video", hue: Palette.signal)
            status = nil
        }
    }
}

/// sheet(item:) needs something Identifiable, and a pad is just a number.
struct PadTarget: Identifiable { let id: Int }
