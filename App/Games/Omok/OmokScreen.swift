import GameCore
import SwiftUI

/// 오목 판. 지금은 자리 표시자이고 Task 6이 판·돌·차례 표시를 채운다.
struct OmokScreen: View {
    let match: OnlineMatch<Omok>
    let onReturn: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 16) {
                HStack {
                    Button(action: onReturn) {
                        Image(systemName: "chevron.left").font(.headline).foregroundStyle(theme.ivory)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityIdentifier("header.menu")
                    .accessibilityLabel("메뉴로")
                    Spacer()
                }
                .padding(.horizontal, 12)
                Spacer()
                Text("오목").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                Spacer()
            }
        }
    }
}
