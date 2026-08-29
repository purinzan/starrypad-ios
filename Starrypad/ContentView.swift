import SwiftUI

struct ContentView: View {
    @StateObject private var midi = MIDIInput()
    @StateObject private var looper = Looper()
    @StateObject private var rack = Rack()
    @StateObject private var recorder = Recorder()
    @State private var player = SamplePlayer()

    @State private var lit: [Int: Double] = [:]          // slot -> energy
    @State private var velocityFloor = 1
    @State private var lastVelocity = 0
    @State private var loaded = 0
    @State private var notes = NoteMap()
    @State private var lastNote: UInt8?

    @State private var panel: Panel?
    @State private var pendingSample: String?
    @State private var draft = PadSlot(id: 0, source: .builtIn(file: ""), label: "", hue: .clear)
    @State private var status: String?
    @State private var pickingVideo = false
    @State private var master = Double(SamplePlayer.defaultMakeupDecibels)
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

    /// Pad 0 is bottom left, so the grid is drawn from the top row down.
    private var rows: [[PadSlot]] {
        let visible = rack.visible
        return stride(from: 12, through: 0, by: -4).map { Array(visible[$0..<($0 + 4)]) }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            bankRow
            if learning { learnBanner }
            // The square grid leaves about 100 points over. Split above and
            // below rather than pooled at the bottom, so the pads sit where
            // your hand already is instead of riding the top edge.
            Spacer(minLength: 0)
            padGrid
            Spacer(minLength: 0)
            ArtSlot(height: 62) { LoopBar(looper: looper) }
            deck
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { deckFrame = proxy.frame(in: .global) }
                    }
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelGround())
        .preferredColorScheme(.dark)
        .onAppear(perform: begin)
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
        .sheet(item: $panel) { which in
            ArtBezel { panelBody(which) }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(PanelGround())
                .presentationDetents([.height(which == .mixer ? 372 : 470), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var padGrid: some View {
        GeometryReader { grid in
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 8) {
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
                player.play(bare, velocity: 110)
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
            onPick: { url in
                pickingVideo = false
                Task { await importVideo(url) }
            },
            onCancel: { pickingVideo = false }
        )
        .ignoresSafeArea()
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(midi.sourceNames.isEmpty ? Palette.ink3 : Palette.signal)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(midi.sourceNames.first ?? "No MIDI in")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(midi.sourceNames.isEmpty ? Palette.ink3 : Palette.ink)
                    .lineLimit(1)
                if let lastNote {
                    Text("note \(lastNote) \u{00b7} \(notes.source.rawValue)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 4)
            // Modes, not destinations: pressing one opens a panel over the
            // instrument and closing it puts you back where you were playing.
            ForEach(Panel.allCases) { which in
                Button { panel = which } label: {
                    ArtButton(label: which.rawValue, hue: Palette.accent,
                              on: panel == which, minHeight: 28)
                        .frame(width: which == .mixer ? 62 : 74)
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
        HStack(spacing: 6) {
            Text("BANK").font(.system(size: 10, weight: .semibold)).kerning(1.4)
                .foregroundStyle(Palette.ink3)
            ForEach(0..<Banks.count, id: \.self) { index in
                Button { rack.selectBank(index) } label: {
                    ArtButton(label: Banks.names[index], hue: Palette.accent,
                              on: index == rack.bank, minHeight: 28)
                        .frame(width: 38)
                }
            }
            Spacer()
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
                ArtButton(label: learning ? "Cancel" : "Learn pads",
                          hue: Palette.danger, on: learning, minHeight: 28)
                    .frame(width: 104)
            }
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
            MixerView(rack: rack, renaming: $renaming,
                      velocityFromForce: $velocityFromForce, force: force,
                      onTune: { player.invalidate(rack.slots[rack.selected].source) },
                      onAudition: { strike(rack.slots[rack.selected], velocity: 110, record: false) })
        case .sampler:
            SamplerView(
                rack: rack, recorder: recorder, player: player,
                pending: $pendingSample, draft: $draft, status: $status,
                onAssign: assignPending,
                onPreview: { player.play(draft, velocity: 110) },
                onPreviewSlot: { strike(rack.slots[rack.selected], velocity: 110, record: false) },
                onPickVideo: { pickingVideo = true },
                onDiscard: { pendingSample = nil; status = nil }
            )
        }
    }

    /// Tempo and master beside the transport, which is where they sit on the
    /// machine this borrows from - and which costs one row instead of two.
    private var deck: some View {
        HStack(alignment: .center, spacing: 10) {
            ArtKnob(value: $looper.bpm, range: 40...240, tint: Palette.accent,
                    caption: "TEMPO", diameter: 42, reading: "\(Int(looper.bpm))")
            ArtKnob(value: $master, range: 0...12, tint: Palette.danger,
                    caption: "MASTER", diameter: 42,
                    reading: String(format: "%+.0f", master),
                    onCommit: { player.makeupDecibels = Float(master) })
            Rectangle().fill(Palette.rule).frame(width: 1, height: 48)
            transport
        }
    }

    private var transport: some View {
        HStack(spacing: 5) {
            transportButton(
                looper.state == .countIn ? "\(looper.countRemaining)" : "Rec",
                tint: Palette.danger,
                on: looper.state == .recording || looper.state == .countIn
            ) {
                looper.toggleRecord()
            }
            transportButton("Play", tint: Palette.accent, on: looper.state == .playing) {
                looper.togglePlay()
            }
            transportButton("Undo", tint: Palette.ink2, on: false,
                            enabled: looper.canUndo || rack.canUndo) {
                // The loop first: while you are playing into it, that is what
                // "undo" means. Pad edits come back once there is nothing left
                // to peel off the take.
                if looper.canUndo { looper.undo() } else { rack.undoEdit() }
            }
            transportButton("Clear", tint: Palette.ink2, on: false,
                            enabled: !looper.events.isEmpty) {
                looper.clear()
            }
        }
    }

    private func transportButton(
        _ label: String, tint: Color, on: Bool, enabled: Bool = true, act: @escaping () -> Void
    ) -> some View {
        Button(action: act) {
            ArtButton(label: label, hue: tint, on: on, enabled: enabled, minHeight: 38)
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
                        .font(.system(size: 11, weight: .semibold)).kerning(0.8)
                        .foregroundStyle(sounding ? .white
                                         : isSelected ? Palette.ink : Palette.ink2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7).lineLimit(2)
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
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isSwapTarget ? Palette.signal
                        : isHeld ? Palette.danger
                        : isSelected ? Palette.accent : .clear,
                        lineWidth: 2)
                    .padding(2)
            )
            .scaleEffect(isHeld ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHeld)
            .shadow(color: Palette.accent.opacity(energy * 0.55), radius: 4 + 12 * energy)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Wiring

    private func begin() {
        loaded = player.preload(Kit.all)
        // Kept even though it is no longer on screen: it is the number that
        // decides whether this feels like an instrument, and it belongs in the
        // log when someone says the app feels slow.
        print(String(format: "output latency %.2f ms", player.outputLatencyMilliseconds))
        player.start()
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
        if record { looper.capture(padID: slot.id, velocity: expanded) }

        let energy = Double(expanded) / 127.0
        lit[slot.id] = energy
        let hold = 0.075 + 0.11 * energy
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(.easeOut(duration: 0.12)) { lit[slot.id] = 0 }
        }
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

    private func importVideo(_ url: URL) async {
        status = "Reading the video…"
        do {
            let name = try await VideoImport.extractAudio(from: url)
            guard player.load(userSample: name) else {
                status = "Could not read that recording"
                return
            }
            pendingSample = name
            draft = PadSlot(id: rack.selected, source: .user(name: name),
                            label: "Video", hue: Palette.signal)
            status = nil
        } catch {
            status = error.localizedDescription
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// sheet(item:) needs something Identifiable, and a pad is just a number.
struct PadTarget: Identifiable { let id: Int }
