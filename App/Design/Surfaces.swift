import SwiftUI

/// 상아색 종이 카드. 점수판, 메뉴 카드, 결과.
struct PaperCard: ViewModifier {
    @Environment(\.theme) private var theme
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(theme.paper)
                    SurfaceTextures.paper.resizable(resizingMode: .tile)
                        .opacity(theme.isDark ? 0.05 : 0.08)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    RoundedRectangle(cornerRadius: 14).strokeBorder(theme.paperLine, lineWidth: 1)
                }
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 8, y: 3)
            }
    }
}

/// 버건디 가죽 패널. 헤더 띠.
struct LeatherPanel: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                theme.leather
                SurfaceTextures.leather.resizable(resizingMode: .tile).opacity(0.12)
                RadialGradient(colors: [.clear, .black.opacity(0.35)],
                               center: .center, startRadius: 40, endRadius: 400)
            }
        }
    }
}

/// 황동 알약 버튼. 버튼 라벨에 건다.
struct BrassButton: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(prominent ? theme.brassInk : theme.brass)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [theme.brass, theme.brass.opacity(0.78)],
                                                  startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(theme.brassInk.opacity(0.35), lineWidth: 1)
                } else {
                    Capsule().strokeBorder(theme.brass, lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension View {
    func paperCard(padding: CGFloat = 16) -> some View { modifier(PaperCard(padding: padding)) }
    func leatherPanel() -> some View { modifier(LeatherPanel()) }
    func brassButton(prominent: Bool = true) -> some View { modifier(BrassButton(prominent: prominent)) }
}

/// 화면 바탕. 호두나무 테이블.
struct WoodBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.table
            SurfaceTextures.wood.resizable(resizingMode: .tile).opacity(theme.isDark ? 0.22 : 0.3)
            RadialGradient(colors: [.clear, .black.opacity(0.45)],
                           center: .center, startRadius: 120, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}
