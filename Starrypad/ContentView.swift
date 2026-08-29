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

    @State private var screen: Screen = .play
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
    @State private var picking: Int?
    @State private var recordings: [String] = []

    @State private var renaming = false
    @State private var taps: [TimeInterval] = []
    @StateObject private var force = StrikeForce()
    @AppStorage("velocityFromForce") private var velocityFromForce = true

    private let holdSeconds = 0.45

    private enum Screen: String, CaseIterable { case play = "Pads", mix = "Mixer", sample = "Sampler" }

    /// Pad 0 is bottom left, so the grid is drawn from the top row down.
    private var rows: [[PadSlot]] {
        let visible = rack.visible
        return stride(from: 12, through: 0, by: -4).map { Array(visible[$0..<($0 + 4)]) }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            bankRow
            if learning { learnBanner }
            padGrid

            ArtSlot(height: 46) { LoopBar(looper: looper) }
            tempoRow
            screenPicker
            ArtBezel {
                ScrollView(.vertical, showsIndicators: false) { detail }
                    // Budgeted against the screen rather than guessed: header,
                    // banks, grid, bar, tempo and picker take about 600 points
                    // of 874, and a panel taller than what is left pushes the
                    // header off the top of the phone.
                    .frame(maxHeight: screen == .play ? 56 : 224)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelGround())
        .preferredColorScheme(.dark)
        .onAppear(perform: begin)
        .sheet(item: pickingBinding) { target in soundPicker(for: target.id) }
        .sheet(isPresented: $pickingVideo) { videoPicker }
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
            .onAppear { gridSize = grid.size }
            .onChange(of: grid.size) { _, size in gridSize = size }
            .overlay(
                PadTouches(onDown: touchDown, onMove: touchMoved, onUp: touchUp)
            )
        }
        // The grid is the instrument. A tall panel below it was squeezing the
        // pads down to a few pixels and letting the loop bar overlap them, so
        // it keeps its room and the panel scrolls inside what is left.
        .frame(minHeight: 260, maxHeight: .infinity)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Panel.art("nameplate").resizable().scaledToFit().frame(height: 24)
                Text(midi.sourceNames.first ?? "No MIDI in")
                    .font(.system(size: 12))
                    .foregroundStyle(midi.sourceNames.isEmpty ? Palette.ink3 : Palette.signal)
                    .lineLimit(1)
                if let lastNote {
                    Text("note \(lastNote) · \(notes.source.rawValue)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer()
            readout("Vel", lastVelocity > 0 ? "\(lastVelocity)" : "—", accent: true)
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

    private var screenPicker: some View {
        HStack(spacing: 6) {
            ForEach(Screen.allCases, id: \.self) { option in
                Button { screen = option } label: {
                    ArtButton(label: option.rawValue, hue: Palette.accent,
                              on: option == screen, minHeight: 34)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch screen {
        case .play:
            transport
        case .mix:
            MixerView(rack: rack, master: $master, renaming: $renaming,
                      velocityFromForce: $velocityFromForce, force: force, looper: looper,
                      onTune: { player.invalidate(rack.slots[rack.selected].source) },
                      onAudition: { strike(rack.slots[rack.selected], velocity: 110, record: false) },
                      onMaster: { player.makeupDecibels = Float(master) })
        case .sample:
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

    /// Tempo, which the count-in and the loop both run on.
    private var tempoRow: some View {
        HStack(spacing: 8) {
            ArtKnob(value: (looper.bpm - 40) / 200, tint: Palette.accent,
                    caption: "TEMPO", reading: "\(Int(looper.bpm))")
            Spacer()
            tempoButton("-") { looper.bpm = max(40, looper.bpm - 1) }
            tempoButton("+") { looper.bpm = min(240, looper.bpm + 1) }
            tempoButton("Tap", wide: true) { tapTempo() }
        }
    }

    private func tempoButton(_ label: String, wide: Bool = false, act: @escaping () -> Void)
        -> some View {
        Button(action: act) {
            ArtButton(label: label, hue: Palette.accent, on: false, minHeight: 30)
                .frame(width: wide ? 56 : 42)
        }
    }

    /// Tempo from the gaps between taps, averaged, with a stale tap starting
    /// a new count rather than dragging the average somewhere silly.
    private func tapTempo() {
        let now = Date().timeIntervalSince1970
        if let last = taps.last, now - last > 2 { taps.removeAll() }
        taps.append(now)
        if taps.count > 5 { taps.removeFirst() }
        guard taps.count >= 2 else { return }
        let gaps = zip(taps, taps.dropFirst()).map { $1 - $0 }
        let average = gaps.reduce(0, +) / Double(gaps.count)
        guard average > 0 else { return }
        looper.bpm = max(40, min(240, (60.0 / average).rounded()))
    }

    private var transport: some View {
        HStack(spacing: 6) {
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
            transportButton("\(looper.bars)B", tint: Palette.ink2, on: false) {
                looper.bars = looper.bars >= 4 ? 1 : looper.bars * 2
            }
            transportButton("Undo", tint: Palette.ink2, on: false, enabled: looper.canUndo) {
                looper.undo()
            }
            transportButton("Clear", tint: Palette.ink2, on: false, enabled: !looper.events.isEmpty) {
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
    }

    /// One finger's worth of press, so two fingers do not share one set of
    /// variables and cancel each other's hold.
    private struct Press {
        var slot: Int
        var origin: Int          // the position it landed on
        var dragged = false
        var target: Int?
    }

    private func touchDown(id: Int, position: Int, depth: Double) {
        let slotID = rack.bank * Banks.padCount + position
        presses[id] = Press(slot: slotID, origin: position)
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
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func touchMoved(id: Int, position: Int?) {
        guard var press = presses[id] else { return }
        if let position, position != press.origin { press.dragged = true }
        if held == press.slot, press.dragged, let position {
            swapTarget = rack.bank * Banks.padCount + position
        }
        press.target = position.map { rack.bank * Banks.padCount + $0 }
        presses[id] = press
    }

    private func touchUp(id: Int) {
        guard let press = presses.removeValue(forKey: id) else { return }
        guard held == press.slot else { return }
        defer { held = nil; swapTarget = nil }
        if press.dragged {
            guard let target = swapTarget, target != press.slot else { return }
            rack.swap(press.slot, target)
            looper.swapPads(press.slot, target)
            player.invalidate(rack.slots[press.slot].source)
            player.invalidate(rack.slots[target].source)
            status = "\(Banks.label(for: press.slot)) and \(Banks.label(for: target)) swapped"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            recordings = Recordings.all()
            picking = press.slot
        }
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
        screen = .play
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
