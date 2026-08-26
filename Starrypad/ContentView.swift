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
    /// Pads with a finger currently down, so a drag fires once and not
    /// every time the touch moves a pixel.
    @State private var touching: Set<Int> = []
    /// Holding a pad. Lift without moving and the sound picker opens; drag to
    /// another pad and the two swap. One gesture, decided by what you do next.
    @State private var held: Int?
    @State private var swapTarget: Int?
    @State private var gridSize: CGSize = .zero
    @State private var picking: Int?
    @State private var recordings: [String] = []

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

            LoopBar(looper: looper)
            screenPicker
            detail
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
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
        }
        .coordinateSpace(name: "grid")
        .frame(maxHeight: .infinity)
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
                Text("STARRYPAD").font(.system(size: 12, weight: .semibold)).kerning(2.4)
                    .foregroundStyle(Palette.accent)
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
            readout("Pad", Banks.label(for: rack.selected), accent: false)
            readout("Vel", lastVelocity > 0 ? "\(lastVelocity)" : "—", accent: true)
            readout("Out", String(format: "%.1f ms", player.outputLatencyMilliseconds), accent: false)
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
                    Text(Banks.names[index])
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(index == rack.bank ? Palette.onAccent : Palette.ink2)
                        .frame(width: 34, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(index == rack.bank ? Palette.accent : Palette.panel))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                            index == rack.bank ? Palette.accent : Palette.rule, lineWidth: 1))
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
                Text(learning ? "Cancel" : "Learn pads")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(learning ? Palette.onAccent : Palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(learning ? Palette.danger : Palette.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(learning ? Palette.danger : Palette.rule, lineWidth: 1))
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
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(option == screen ? Palette.onAccent : Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(option == screen ? Palette.accent : Palette.panel))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                            option == screen ? Palette.accent : Palette.rule, lineWidth: 1))
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
            MixerView(rack: rack, master: $master,
                      onTune: { player.invalidate(rack.slots[rack.selected].source) },
                      onAudition: { strike(rack.slots[rack.selected], velocity: 110, record: false) },
                      onMaster: { player.makeupDecibels = Float(master) })
        case .sample:
            SamplerView(
                rack: rack, recorder: recorder, player: player,
                pending: $pendingSample, draft: $draft, status: $status,
                onAssign: assignPending,
                onPreview: { player.play(draft, velocity: 110) },
                onPickVideo: { pickingVideo = true },
                onDiscard: { pendingSample = nil; status = nil }
            )
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            transportButton("Rec", tint: Palette.danger, on: looper.state == .recording) {
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
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Palette.onAccent : enabled ? Palette.ink : Palette.ink3)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? tint : Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(on ? tint : Palette.rule, lineWidth: 1))
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
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8).fill(sounding ? Palette.padHit : Palette.pad)
                RoundedRectangle(cornerRadius: 8).fill(Palette.accentSoft.opacity(energy * 0.85))
                Rectangle()
                    .fill(Palette.hueHint(slot.hue))
                    .frame(height: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
                VStack(spacing: 3) {
                    Text(slot.label.uppercased())
                        .font(.system(size: 11, weight: .semibold)).kerning(0.8)
                        .foregroundStyle(sounding ? Palette.accent
                                         : isSelected ? Palette.ink : Palette.ink2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7).lineLimit(2)
                    if case .user = slot.source {
                        Text("SAMPLE").font(.system(size: 8, weight: .semibold)).kerning(1)
                            .foregroundStyle(Palette.signal)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(learning && !wanted ? 0.25 : silent ? 0.45 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSwapTarget ? Palette.signal
                        : isHeld ? Palette.danger
                        : sounding || isSelected ? Palette.accent : Palette.rule,
                        lineWidth: isHeld || isSwapTarget || sounding || isSelected ? 2 : 1)
            )
            .scaleEffect(isHeld ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHeld)
            .shadow(color: Palette.accent.opacity(energy * 0.55), radius: 4 + 12 * energy)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
                    // onChanged, not onEnded: the first event of a drag is the
                    // touch landing, and a drum that sounds when you lift your
                    // finger is not a drum.
                    .onChanged { touch in
                        if !touching.contains(slot.id) {
                            touching.insert(slot.id)
                            // Touch carries no velocity, so the pad does: the
                            // higher up you hit it, the harder it lands.
                            let local = touch.location.y - geometry.frame(in: .named("grid")).minY
                            let depth = 1.0 - min(max(local / geometry.size.height, 0), 1)
                            rack.selected = slot.id
                            strike(slot, velocity: 24 + Int(depth * 103))
                            beginHoldTimer(for: slot.id)
                        }
                        if held == slot.id {
                            swapTarget = position(at: touch.location).map {
                                rack.bank * Banks.padCount + $0
                            }
                        }
                    }
                    .onEnded { _ in
                        touching.remove(slot.id)
                        finishHold(from: slot.id)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Wiring

    private func begin() {
        loaded = player.preload(Kit.pads)
        player.start()
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
    }

    /// A held pad that has not moved yet opens the picker; one dragged onto
    /// another swaps the two.
    private func beginHoldTimer(for id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            guard touching.contains(id), held == nil else { return }
            held = id
            swapTarget = id
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func finishHold(from id: Int) {
        defer { held = nil; swapTarget = nil }
        guard held == id else { return }
        if let target = swapTarget, target != id {
            rack.swap(id, target)
            looper.swapPads(id, target)
            player.invalidate(rack.slots[id].source)
            player.invalidate(rack.slots[target].source)
            status = "\(Banks.label(for: id)) and \(Banks.label(for: target)) swapped"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            recordings = Recordings.all()
            picking = id
        }
    }

    /// Which position in the grid a point in the grid's own space falls on.
    private func position(at point: CGPoint) -> Int? {
        guard gridSize.width > 0, gridSize.height > 0 else { return nil }
        let column = Int(point.x / (gridSize.width / 4))
        let row = Int(point.y / (gridSize.height / 4))
        guard (0..<4).contains(column), (0..<4).contains(row) else { return nil }
        // Row 0 is the top of the screen, which is the last row of positions.
        return (3 - row) * 4 + column
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
        rack.assign(name, label: draft.label, to: target)
        rack.slots[target].start = draft.start
        rack.slots[target].end = draft.end
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
