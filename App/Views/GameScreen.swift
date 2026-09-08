import SwiftUI
import YachtCore
import DiceTrajectory

struct GameScreen: View {
    let session: GameSession
    let stage: DiceStage
    var onReturnToMenu: () -> Void = {}

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback = FeedbackCoordinator()
    /// 점수판에 펼친 좌석. nil이면 현재 차례를 따라간다.
    @State private var viewedSeat: Int?
    /// 턴이 바뀔 때 잠깐 보이는 배너.
    @State private var turnBanner: String?
    @State private var bannerTask: Task<Void, Never>?
    /// 상대가 방금 기록한 칸과 점수. 헤더 아래에 잠깐 뜬다.
    @State private var scoreToast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WoodBackground()
                VStack(spacing: 0) {
                    header
                    if session.participants.count > 1 {
                        PlayerStrip(session: session, viewedSeat: viewedSeat) { seat in
                            viewedSeat = seat == session.visibleState.currentPlayer ? nil : seat
                        }
                        .padding(.vertical, 8)
                    }
                    DiceStageView(stage: stage) { slot in
                        Task { await session.send(.toggleHold(slot)) }
                    }
                    .frame(height: geometry.size.height * (session.participants.count > 1 ? 0.37 : 0.41))
                    .contentShape(Rectangle())
                    .gesture(throwGesture)
                    .overlay(alignment: .top) { edgeShadow(.top) }
                    .overlay(alignment: .bottom) { edgeShadow(.bottom) }
                    Group {
                        if session.visibleState.phase == .finished {
                            GameOverBar(session: session, onReturnToMenu: onReturnToMenu)
                        } else {
                            ActionBarView(session: session)
                        }
                    }
                    .padding(.vertical, 12)
                    ScrollView {
                        ScoreboardView(session: session, seat: viewedSeat)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = session.lastTransportError {
                    Text(error)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                        .padding(.top, 48)
                        .accessibilityIdentifier("online.error")
                }
            }
            .overlay {
                if session.pendingHandoff {
                    HandoffOverlay(playerName: session.currentParticipant.displayName) {
                        session.acknowledgeHandoff()
                    }
                }
            }
            .overlay {
                if let turnBanner {
                    TurnBanner(text: turnBanner)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let scoreToast {
                    ScoreToast(text: scoreToast)
                        .padding(.top, session.participants.count > 1 ? 118 : 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onChange(of: session.visibleState.currentPlayer, initial: true) { _, seat in
            viewedSeat = nil
            showTurnBanner(for: seat)
        }
        .onChange(of: session.lastOpponentCommit?.id) { _, _ in
            guard let commit = session.lastOpponentCommit else { return }
            let name = session.participants[commit.seat].displayName
            showScoreToast("\(name): \(commit.category.displayName) \(commit.points)점 기록")
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            session.reduceMotion = newValue
        }
        .task { feedback.attach(session) }
    }

    /// 2인 이상일 때 턴이 바뀌면 누구 차례인지 1.6초 동안 크게 보여준다. 패스앤플레이는 핸드오프가 대신한다.
    private func showTurnBanner(for seat: Int) {
        guard session.participants.count > 1, session.visibleState.phase != .finished,
              !session.pendingHandoff else { return }
        let participant = session.participants[seat]
        let text = participant.isHuman && session.isLocalTurn ? "내 차례" : "\(participant.displayName)의 차례"
        bannerTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { turnBanner = text }
        bannerTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { turnBanner = nil }
        }
    }

    /// 상대나 봇이 기록한 칸과 점수를 2초 동안 보여준다.
    private func showScoreToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { scoreToast = text }
        toastTask = Task {
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { scoreToast = nil }
        }
    }

    /// 3D 무대와 화면을 이어 붙이는 얇은 그림자.
    private func edgeShadow(_ edge: Edge) -> some View {
        LinearGradient(colors: [.black.opacity(0.35), .clear],
                       startPoint: edge == .top ? .top : .bottom,
                       endPoint: edge == .top ? .bottom : .top)
            .frame(height: 14)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onReturnToMenu) {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(theme.ivory)
                    .frame(width: 32, height: 32)
            }
            .accessibilityIdentifier("header.menu")
            .accessibilityLabel("메뉴로")
            VStack(alignment: .leading, spacing: 4) {
                // combine을 이 Group에만 걸어서 header.turn의 label이 항상 턴
                // 텍스트가 되게 한다. 바깥 HStack 전체에 걸면 "게임 종료"까지
                // 합쳐져서 두 상태를 구분할 라벨도, 별도로 찾을 static text도
                // 없어진다.
                Group {
                    Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(theme.ivory)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("header.turn")
                .accessibilityRemoveTraits(.isStaticText)
                TurnProgress(current: session.visibleState.turnIndex - (session.visibleState.phase == .finished ? 0 : 1),
                             total: YachtCore.turnCount)
                    .frame(width: 120)
            }
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(theme.brass)
            } else if case .bot = session.currentParticipant {
                Text("컴퓨터가 생각 중").font(.subheadline).foregroundStyle(theme.ivory.opacity(0.8))
                    .accessibilityIdentifier("header.status")
            } else if case .remote = session.currentParticipant {
                Text("상대 차례").font(.subheadline).foregroundStyle(theme.ivory.opacity(0.8))
                    .accessibilityIdentifier("header.status")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .leatherPanel()
    }

    /// 위로 쓸어올리면 던진다. 좌우 성분으로 궤적 그룹을 고른다.
    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                // 아래로 쓸어내린 것은 던지기가 아니다
                guard value.translation.height < -20 else { return }
                let horizontal = value.translation.width
                session.nextThrowDirection = if horizontal < -40 {
                    .left
                } else if horizontal > 40 {
                    .right
                } else {
                    .center
                }
                Task { await session.send(.roll) }
            }
    }
}
