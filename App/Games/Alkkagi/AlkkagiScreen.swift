import SwiftUI
import GameCore

/// 알까기 한 판. 판이 열리면 먼저 제 진영에 돌 다섯을 놓고, 그다음부터는
/// 내 돌을 잡아 당겼다 놓으면 새총처럼 반대로 튕겨 나가고,
/// 시뮬레이션이 만든 프레임을 30fps로 재생한다 — 로컬 2인은 한 기기에서 좌석이 번갈아 넘어간다.
struct AlkkagiScreen: View {
    let match: OnlineMatch<Alkkagi>
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// 잡은 돌과 손가락의 격자 위치. 배치 중에는 초안의 돌을, 튕길 때는 판 위의 돌을 가리킨다.
    @State private var grabbed: Int?
    @State private var finger: Alkkagi.Point?
    /// 확정하기 전의 내 배치. 내가 놓을 차례가 되면 기본 배치로 시작한다.
    @State private var draft: [Alkkagi.Point] = []
    /// 재생 중인 프레임의 배치. nil이면 상태의 배치를 그린다.
    @State private var playing: [[Alkkagi.Point?]]?
    /// 재생 중인 수를 둔 좌석. 수는 먼저 판에 들어가므로 머리글은 상태가 아니라 이 좌석을 따라간다.
    @State private var replayingSeat: Int?
    @State private var isPlaying = false
    @State private var turnBanner: String?
    @State private var toast: String?
    /// 채널이 3초 넘게 끊겨 있을 때만 띠를 보인다. 짧은 재접속은 조용히 지나간다.
    @State private var showDisconnected = false
    @State private var disconnectTask: Task<Void, Never>?

    private var seatNames: [String] { match.participants.map(\.displayName) }
    /// 화면이 그리는 배치. 재생 중이면 프레임, 배치 중이면 아직 확정하지 않은 내 초안을 얹은 상태,
    /// 아니면 상태의 것이다. 머리글과 명패의 숫자도 모두 여기서 센다.
    private var displayedStones: [[Alkkagi.Point?]] {
        if let playing { return playing }
        var stones = match.state.stones
        // 상대가 놓는 동안에도 내 초안은 보인다 — 상대 돌은 이미 판에 놓인 것만 그려진다.
        if match.state.phase == .setup, !match.state.placed[mySeat] { stones[mySeat] = myDraft.map { Optional($0) } }
        return stones
    }
    /// 지금 놓아야 하는 좌석. 배치가 끝났으면 nil이다.
    private var placingSeat: Int? { match.state.phase == .setup ? Alkkagi.currentSeat(match.state) : nil }
    /// 내가 놓을 차례인가.
    private var isMyPlacement: Bool { placingSeat == mySeat && match.isLocalTurn }
    /// 그릴 내 배치. `draft`가 아직 채워지기 전 한 프레임에도 기본 배치가 보인다.
    private var myDraft: [Alkkagi.Point] {
        draft.count == Alkkagi.stonesPerSeat ? draft : Alkkagi.defaultPlacement(seat: mySeat)
    }
    /// 배치 중에 끌고 있는 내 돌. 놓기 전까지는 초안이 아니라 손끝에 그린다.
    private var draggingDraft: (seat: Int, stone: Int, at: Alkkagi.Point)? {
        guard match.state.phase == .setup, isMyPlacement, let grabbed, let finger else { return nil }
        return (mySeat, grabbed, finger)
    }
    /// 화면이 보이는 차례. 수는 재생을 기다리지 않고 먼저 들어가므로, 재생 중에는 튕긴 좌석을 그대로 든다.
    private var displayedSeat: Int? { playing != nil ? replayingSeat : Alkkagi.currentSeat(match.state) }
    private func displayedRemaining(seat: Int) -> Int { displayedStones[seat].compactMap { $0 }.count }
    /// 판이 끝나면 차례가 없어 좌석을 잃는다. 로컬은 보이는 좌석을, 끝난 뒤에는 이긴 좌석을 시점으로 삼아 "내 돌"이 뒤바뀌지 않게 한다.
    private var mySeat: Int {
        if match.mode.isOnline { return match.localSeat ?? 0 }
        if let seat = displayedSeat { return seat }
        if case .win(let seat)? = match.outcome { return seat }
        return 0
    }
    /// 온라인의 좌석 1은 내 돌이 아래에 오게 판을 돌린다.
    private var flipped: Bool { match.mode.isOnline && match.localSeat == 1 }

    /// 잡은 돌에서 손가락까지가 당김이다. 놓으면 반대 방향으로 날아간다.
    private var pull: (from: Alkkagi.Point, to: Alkkagi.Point)? {
        guard match.state.phase == .play, let grabbed, let finger,
              let seat = Alkkagi.currentSeat(match.state), let from = match.state.stones[seat][grabbed] else { return nil }
        return (from, finger)
    }
    /// 화면에 그리는 당김. 최대를 넘긴 만큼은 잘라 내 힘이 1000에 묶인 뒤로는 선도 자라지 않는다.
    private var drawnPull: (from: Alkkagi.Point, to: Alkkagi.Point, clamped: Bool)? {
        guard let pull else { return nil }
        let to = AlkkagiGeometry.clampPull(from: pull.from, to: pull.to)
        return (pull.from, to, to != pull.to)
    }
    /// 당기는 동안에만 시뮬레이션을 돌려 앞 40프레임의 길을 미리 보인다. 잡은 돌이 없으면 한 번도 돌지 않는다.
    private var previewPath: [Alkkagi.Point] {
        guard let pull, let grabbed, let seat = Alkkagi.currentSeat(match.state),
              let flick = AlkkagiGeometry.flick(stone: grabbed, from: pull.from, to: pull.to) else { return [] }
        let sim = Alkkagi.simulate(match.state, flick)
        return sim.frames.prefix(40).compactMap { $0.stones[seat][grabbed] }
    }

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 10) {
                header
                seats
                GeometryReader { proxy in
                    AlkkagiBoardView(stones: displayedStones, flipped: flipped, pull: drawnPull, preview: previewPath,
                                     highlight: grabbed, highlightSeat: displayedSeat ?? 0,
                                     homeShade: placingSeat.map { Alkkagi.homeRange(seat: $0) }, dragging: draggingDraft)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(size: proxy.size))
                }
                .aspectRatio(1, contentMode: .fit)
                actionBar
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) {
                if showDisconnected {
                    Label("연결 끊김 — 재연결 중", systemImage: "wifi.slash").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(theme.ink.opacity(0.85), in: Capsule())
                        .foregroundStyle(theme.paper).padding(.top, 118).accessibilityIdentifier("online.connection")
                }
            }
            .overlay(alignment: .top) {
                if let error = match.lastTransportError {
                    Text(error).font(.caption).padding(8).background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white).padding(.top, 48).accessibilityIdentifier("online.error")
                }
            }
            .overlay { if let turnBanner { TurnBanner(text: turnBanner).transition(.scale(scale: 0.9).combined(with: .opacity)) } }
            .overlay(alignment: .top) {
                if let toast { ScoreToast(text: toast).padding(.top, 118).transition(.move(edge: .top).combined(with: .opacity)) }
            }
        }
        // 훅이 match를 강하게 담으면 match → onRemoteMove → match 고리가 되어, 판을 떠나도 세션이 살아남는다.
        .task { [weak match, playing = $playing, isPlaying = $isPlaying, replayingSeat = $replayingSeat] in
            guard let match else { return }
            match.onRemoteMove = { [weak match] move, _ in
                // 배치는 재생할 움직임이 없다 — 판에 돌이 놓인 것은 상태가 바뀌며 그대로 그려진다.
                guard let match, case .flick(let flick) = move else { return }
                // 훅은 수가 로그에 붙기 전에 불리므로 여기의 state는 수 전 배치다 — apply와 같은 재생이 나오고 좌석도 튕긴 쪽이다.
                let seat = Alkkagi.currentSeat(match.state) ?? 0
                let sim = Alkkagi.simulate(match.state, flick)
                await Self.replay(sim, seat: seat, playing: playing, isPlaying: isPlaying, replayingSeat: replayingSeat)
            }
        }
        .onDisappear { match.onRemoteMove = nil }
        .onChange(of: match.log.moves.count, initial: true) { _, _ in
            // 재생 중에 뜨면 배너가 날아가는 돌을 덮는다. 내 튕김은 재생이 끝난 뒤 Task가 다시 부르고,
            // 상대 수는 훅의 재생이 끝난 다음에 로그가 붙어 여기서 그대로 불린다.
            guard !isPlaying else { return }
            announceTurn()
        }
        .onChange(of: placingSeat, initial: true) { _, seat in
            // 내가 놓을 차례가 되면 기본 배치에서 시작한다 — 로컬 2인은 좌석이 넘어갈 때마다 다시 채운다.
            guard let seat, seat == mySeat else { return }
            draft = Alkkagi.defaultPlacement(seat: seat)
        }
        .onChange(of: match.lastRemoteMove?.id) { _, _ in
            guard let remote = match.lastRemoteMove, let sim = match.state.lastSimulation else { return }
            // 튕긴 사람이 제 돌을 떨어뜨린 것은 세지 않는다 — 몇 개를 앗겼는지만 알린다.
            let dropped = sim.events.filter { if case .dropped(let ref) = $0.kind { ref.seat != remote.seat } else { false } }.count
            showToast(dropped == 0 ? "\(seatNames[remote.seat]): 빗나감" : "\(seatNames[remote.seat]): 돌 \(dropped)개 떨어뜨림")
        }
        .onChange(of: match.isConnected, initial: true) { _, connected in
            disconnectTask?.cancel()
            if connected { withAnimation { showDisconnected = false } }
            else { disconnectTask = Task { try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; withAnimation { showDisconnected = true } } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await match.resync() } } }
    }

    /// 머리글은 한 줄이다 — 판이 화면 폭과 높이를 최대한 쓰게 남은 자리를 줄인다.
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                .accessibilityIdentifier("header.menu").accessibilityLabel("메뉴로")
            Text("알까기").font(.system(.headline, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
            Spacer(minLength: 4)
            Text(statusText)
                .font(.caption).monospacedDigit().foregroundStyle(theme.brass).accessibilityIdentifier("header.status")
            Text(turnText)
                .font(.caption).foregroundStyle(theme.ivory).accessibilityIdentifier("header.turn")
        }
        .lineLimit(1)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// 배치 중에는 남은 돌을 세어 봐야 소용이 없다 — 무엇을 하는 단계인지만 적는다.
    private var statusText: String {
        guard match.state.phase == .play else { return "배치 중" }
        return "내 돌 \(displayedRemaining(seat: mySeat)) · 상대 돌 \(displayedRemaining(seat: 1 - mySeat))"
    }

    private var turnText: String {
        guard let seat = displayedSeat else { return "끝" }
        return match.state.phase == .setup ? "\(seatNames[seat]) 배치" : "\(seatNames[seat]) 차례"
    }

    /// 명패 둘. 한 줄 높이 28pt이고 현재 차례는 황동, 원격 상대는 접속 점. 숫자는 그 좌석에 남은 돌이다.
    private var seats: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { seat in
                let current = displayedSeat == seat
                HStack(spacing: 6) {
                    if case .remote = match.participants[seat] {
                        Circle().fill(match.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5)).frame(width: 7, height: 7)
                            .accessibilityIdentifier("players.presence.\(seat)")
                    }
                    Text(seatNames[seat]).font(.caption).lineLimit(1)
                    Text("\(displayedRemaining(seat: seat))").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(current ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(current ? theme.brass : theme.paper))
                .accessibilityIdentifier("players.seat.\(seat)")
                .accessibilityLabel("\(seatNames[seat]), 돌 \(displayedRemaining(seat: seat))개\(current ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var actionBar: some View {
        // 결과 카드는 재생이 끝난 뒤에 올린다 — 마지막 돌이 아직 굴러가는데 승패부터 뜨면 김이 샌다.
        if let outcome = match.outcome, playing == nil {
            VStack(spacing: 10) {
                Text(resultText(outcome)).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("alkkagi.result")
                Button(action: onReturn) { Label("메뉴로", systemImage: "chevron.left").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).accessibilityIdentifier("alkkagi.back")
            }
            .paperCard(padding: 14).padding(.horizontal, 16)
        } else if let placingSeat {
            VStack(spacing: 8) {
                Text(isMyPlacement ? "내 돌을 진영 안에 놓는다" : "\(seatNames[placingSeat])이(가) 돌을 놓는 중")
                    .font(.caption).foregroundStyle(theme.ivory)
                Button(action: placeDraft) { Text("배치 완료").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).disabled(!canPlace).accessibilityIdentifier("alkkagi.placeDone")
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        } else {
            Text(displayedSeat == mySeat ? "내 돌을 당겨 놓는다" : "\(seatNames[displayedSeat ?? 0])의 차례를 기다린다")
                .font(.caption).foregroundStyle(theme.ivory).padding(.bottom, 8)
        }
    }

    /// 내 차례이고 초안이 규칙에 맞을 때만 확정할 수 있다.
    private var canPlace: Bool { isMyPlacement && Alkkagi.placementIsValid(myDraft, seat: mySeat) }

    private func placeDraft() {
        let points = myDraft
        // 좌석이 넘어간 뒤에 눌린 늦은 탭은 규칙이 거절한다 — 화면은 그 사실만 알린다.
        Task { if await match.play(.setup(points)) == false { showToast("지금은 놓을 수 없다") } }
    }

    /// 손끝이 하는 일은 단계가 가른다 — 배치에서는 초안의 돌을 옮기고, 튕길 때는 새총을 당긴다.
    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard match.state.phase == .play else { return setupDragChanged(value, size: size) }
                guard match.isLocalTurn, !isPlaying, let seat = Alkkagi.currentSeat(match.state) else { return }
                if grabbed == nil {
                    grabbed = AlkkagiGeometry.stone(at: value.startLocation, stones: match.state.stones[seat], in: size, flipped: flipped)
                }
                guard grabbed != nil else { return }
                finger = AlkkagiGeometry.point(at: value.location, in: size, flipped: flipped)
            }
            .onEnded { value in
                guard match.state.phase == .play else { return setupDragEnded(value, size: size) }
                defer { grabbed = nil; finger = nil }
                guard match.isLocalTurn, !isPlaying, let grabbed, let seat = Alkkagi.currentSeat(match.state),
                      let from = match.state.stones[seat][grabbed] else { return }
                // 점선이 그리던 그 점에서 힘을 얻는다 — 마지막으로 본 손가락과 놓은 자리가 어긋나도 본 대로 날아간다.
                let to = finger ?? AlkkagiGeometry.point(at: value.location, in: size, flipped: flipped)
                guard let flick = AlkkagiGeometry.flick(stone: grabbed, from: from, to: to) else { return }
                let sim = Alkkagi.simulate(match.state, flick)
                // 잠금은 Task를 만들기 전에 건다. 그 사이에 두 번째 당김이 들어오면 돌이 두 번 날아간다.
                isPlaying = true
                replayingSeat = seat
                // 수는 재생을 기다리지 않고 먼저 판에 넣는다 — 상대가 내 애니메이션(길어야 1.5초)을 기다릴 일이 아니다.
                // 첫 프레임을 미리 그려 두었으니 play가 상태를 바꾸어도 튕기기 전 배치가 비치지 않는다.
                playing = sim.frames.first?.stones
                Task {
                    async let animation: Void = Self.replay(sim, seat: seat, playing: $playing, isPlaying: $isPlaying,
                                                            replayingSeat: $replayingSeat)
                    let played = await match.play(.flick(flick))
                    if !played { showToast("지금은 튕길 수 없다") }
                    await animation
                    // 돌이 멎은 뒤에 다음 차례를 알린다 — 로그가 붙던 때는 재생 중이라 배너를 미뤘다.
                    announceTurn()
                }
            }
    }

    /// 배치 중의 끌기. 내 초안의 돌을 잡아 손끝을 따라다니게 한다.
    private func setupDragChanged(_ value: DragGesture.Value, size: CGSize) {
        guard isMyPlacement else { return }
        if grabbed == nil {
            grabbed = AlkkagiGeometry.stone(at: value.startLocation, stones: myDraft.map { Optional($0) },
                                            in: size, flipped: flipped)
        }
        guard grabbed != nil else { return }
        finger = AlkkagiGeometry.point(at: value.location, in: size, flipped: flipped)
    }

    /// 놓는 순간 가장 가까운 교차점에 붙인다. 진영을 벗어나거나 다른 돌에 닿는 자리면 그 돌만 있던 자리로 되돌아간다.
    private func setupDragEnded(_ value: DragGesture.Value, size: CGSize) {
        defer { grabbed = nil; finger = nil }
        guard isMyPlacement, let grabbed else { return }
        let to = AlkkagiGeometry.snap(finger ?? AlkkagiGeometry.point(at: value.location, in: size, flipped: flipped))
        var next = myDraft
        next[grabbed] = to
        guard Alkkagi.placementIsValid(next, seat: mySeat) else { return }
        draft = next
    }

    private func resultText(_ outcome: Outcome) -> String {
        guard case .win(let seat) = outcome else { return "무승부" }
        if match.mode.isOnline { return match.localSeat == seat ? "승리!" : "패배" }
        return "\(seatNames[seat]) 승리"
    }

    /// 프레임을 30fps로 재생하고 충돌·낙하 프레임에 소리와 햅틱을 낸다. 내 튕김과 상대 재생이 같은 길을 쓴다.
    ///
    /// 화면 상태 바인딩만 받는 정적 함수다. 훅이 뷰 값을 담으면 그 안의 `match`까지 함께 잡힌다.
    @MainActor
    private static func replay(_ sim: Alkkagi.Simulation, seat: Int, playing: Binding<[[Alkkagi.Point?]]?>,
                               isPlaying: Binding<Bool>, replayingSeat: Binding<Int?>) async {
        isPlaying.wrappedValue = true
        replayingSeat.wrappedValue = seat
        var eventIndex = 0
        for i in sim.frames.indices {
            playing.wrappedValue = sim.frames[i].stones
            for event in eventsToPlay(in: sim, frame: i, from: &eventIndex) {
                switch event.kind {
                case .collision: SoundPlayer.shared.play(SoundSynth.clack(), key: "clack"); Haptics.shared.play(.impactMedium)
                case .dropped: SoundPlayer.shared.play(SoundSynth.drop(), key: "drop"); Haptics.shared.play(.impactHeavy)
                }
            }
            // 화면을 떠나 재생이 끊기면 남은 프레임과 소리를 버린다. 배치는 아래에서 상태의 것으로 되돌린다.
            do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
        }
        playing.wrappedValue = nil
        isPlaying.wrappedValue = false
        replayingSeat.wrappedValue = nil
    }

    /// i번째 프레임에서 낼 사건들. 사건은 스텝으로 프레임에 짝지으며, 마지막 프레임은 스텝이
    /// frameEvery의 배수가 아닐 수 있어 남은 사건을 모두 가져간다. 순수 함수라 테스트한다.
    static func eventsToPlay(in sim: Alkkagi.Simulation, frame i: Int, from eventIndex: inout Int) -> [Alkkagi.Event] {
        let stepEnd = i == sim.frames.count - 1 ? sim.steps : i * Alkkagi.frameEvery
        var due: [Alkkagi.Event] = []
        while eventIndex < sim.events.count, sim.events[eventIndex].step <= stepEnd {
            due.append(sim.events[eventIndex])
            eventIndex += 1
        }
        return due
    }

    /// 지금 차례를 배너로 알린다. 판이 끝났으면 알릴 차례가 없다.
    private func announceTurn() {
        guard match.outcome == nil, let seat = Alkkagi.currentSeat(match.state) else { return }
        // 배치는 누가 놓을 차례인지가 전부라 온라인에서도 이름을 부른다.
        guard match.state.phase == .play else { return showBanner("\(seatNames[seat]) 배치") }
        // 로컬 2인은 두 좌석 다 내 것이라 "내 차례"가 아무것도 알려주지 않는다. 이름을 부른다.
        showBanner(match.mode.isOnline && match.isLocalTurn ? "내 차례" : "\(seatNames[seat]) 차례")
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { turnBanner = text }
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation(.easeOut(duration: 0.3)) { if turnBanner == text { turnBanner = nil } } }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { if toast == text { toast = nil } } }
    }
}
