import SwiftUI
import UIKit

/// 판 위에 얹는 겹층. 반응마다 이모지가 크게 떠올라 위로 흩어지며 2초 안에 사라지고, 입력은 판으로 지나간다.
/// 상대의 반응이면 가볍게 떨리고, VoiceOver가 켜져 있으면 누가 무엇을 보냈는지 읽어 준다.
struct ReactionOverlay: View {
    let board: ReactionBoard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(board.bursts) { burst in
                ReactionBurstView(emoji: burst.emoji, reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: board.bursts.last?.id) { _, _ in
            guard let burst = board.bursts.last, burst.seat == board.remoteSeat else { return }
            Haptics.shared.play(.selection)
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement("\(board.remoteName): \(burst.emoji)").post()
            }
        }
    }
}

/// 한 번의 떠오름. 큰 이모지 하나와 작은 사본 둘이 위로 흩어진다. 동작 줄이기면 제자리에서 나타났다 사라진다.
private struct ReactionBurstView: View {
    let emoji: String
    let reduceMotion: Bool
    /// 나타날 때 한 번 바뀌어 키프레임을 한 번만 돌린다. 방아쇠가 없는 키프레임은 끝나면 처음부터 되풀이한다.
    @State private var started = false

    private struct Frame {
        var rise: CGFloat = 0
        var spread: CGFloat = 0
        var scale: CGFloat = 0.6
        var opacity: Double = 0
    }

    var body: some View {
        ZStack {
            Text(emoji).font(.system(size: 36)).modifier(Drift(x: -0.45, y: -0.65, alpha: 0.6))
            Text(emoji).font(.system(size: 30)).modifier(Drift(x: 0.4, y: -0.8, alpha: 0.5))
            Text(emoji).font(.system(size: 64))
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .keyframeAnimator(initialValue: Frame(), trigger: started) { content, frame in
            content
                .environment(\.reactionSpread, reduceMotion ? 0 : frame.spread)
                .offset(y: reduceMotion ? 0 : -frame.rise)
                .scaleEffect(reduceMotion ? 1 : frame.scale)
                .opacity(frame.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.rise) { CubicKeyframe(140, duration: 2) }
            KeyframeTrack(\.spread) { CubicKeyframe(120, duration: 2) }
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.15, duration: 0.3)
                CubicKeyframe(1.0, duration: 1.7)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 1.05)
                LinearKeyframe(0, duration: 0.8)
            }
        }
        .onAppear { started = true }
        .accessibilityIdentifier("reaction.burst")
        .accessibilityLabel(emoji)
    }
}

/// 작은 사본이 퍼져 나가는 정도. 떠오름의 키프레임이 정하고 사본이 읽는다.
private struct ReactionSpreadKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private extension EnvironmentValues {
    var reactionSpread: CGFloat {
        get { self[ReactionSpreadKey.self] }
        set { self[ReactionSpreadKey.self] = newValue }
    }
}

private struct Drift: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    let alpha: Double
    @Environment(\.reactionSpread) private var spread
    func body(content: Content) -> some View {
        content.offset(x: x * spread, y: y * spread).opacity(spread == 0 ? 0 : alpha)
    }
}

/// 명패 오른쪽 위 모서리의 반응 배지.
private struct ReactionBadge: ViewModifier {
    let emoji: String?
    let seat: Int
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if let emoji {
                    Text(emoji).font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.paper).shadow(color: .black.opacity(0.35), radius: 3, y: 1))
                        .offset(x: 6, y: -10)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("reaction.badge.\(seat)")
                        .accessibilityLabel("반응 \(emoji)")
                }
            }
            .animation(.spring(duration: 0.3), value: emoji)
    }
}

extension View {
    /// 명패에 그 좌석의 마지막 반응을 배지로 붙인다. nil이면 아무것도 그리지 않는다.
    func reactionBadge(_ emoji: String?, seat: Int) -> some View {
        modifier(ReactionBadge(emoji: emoji, seat: seat))
    }
}
