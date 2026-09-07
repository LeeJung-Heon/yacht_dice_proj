import SwiftUI
import YachtCore
import DiceTrajectory

struct GameScreen: View {
    let session: GameSession
    let stage: DiceStage
    var onReturnToMenu: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if session.participants.count > 1 {
                    PlayerStrip(session: session).padding(.bottom, 6)
                }
                DiceStageView(stage: stage) { slot in
                    Task { await session.send(.toggleHold(slot)) }
                }
                .frame(height: geometry.size.height * (session.participants.count > 1 ? 0.38 : 0.42))
                .contentShape(Rectangle())
                .gesture(throwGesture)
                Group {
                    if session.visibleState.phase == .finished {
                        GameOverBar(session: session, onReturnToMenu: onReturnToMenu)
                    } else {
                        ActionBarView(session: session)
                    }
                }
                .padding(.vertical, 10)
                Divider()
                ScrollView {
                    ScoreboardView(session: session)
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
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            session.reduceMotion = newValue
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                onReturnToMenu()
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .accessibilityIdentifier("header.menu")
            .accessibilityLabel("메뉴로")
            // combine을 이 Group에만 걸어서 header.turn의 label이 항상 턴
            // 텍스트가 되게 한다. 바깥 HStack 전체에 걸면 "게임 종료"까지
            // 합쳐져서 두 상태를 구분할 라벨도, 별도로 찾을 static text도
            // 없어진다.
            Group {
                Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("header.turn")
            .accessibilityRemoveTraits(.isStaticText)
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(.green)
            } else if case .bot = session.currentParticipant {
                Text("컴퓨터가 생각 중").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("header.status")
            } else if case .remote = session.currentParticipant {
                Text("상대 차례").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("header.status")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
