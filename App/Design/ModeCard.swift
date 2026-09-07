import SwiftUI

/// 메뉴의 모드 카드. 카드 전체가 버튼이다.
struct ModeCard<Accessory: View>: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let subtitle: String
    /// 카드 안 버튼의 접근성 식별자. 컨테이너에 걸면 탭이 버튼에 닿지 않는다.
    var identifier: String? = nil
    var expanded = false
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(theme.brass)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
                        Text(subtitle).font(.caption).foregroundStyle(theme.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.inkSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier ?? "")
            .accessibilityValue(expanded ? "펼침" : "")
            accessory()
        }
        .paperCard(padding: 14)
    }
}

extension ModeCard where Accessory == EmptyView {
    init(icon: String, title: String, subtitle: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.init(icon: icon, title: title, subtitle: subtitle, identifier: identifier, expanded: false, action: action) { EmptyView() }
    }
}
