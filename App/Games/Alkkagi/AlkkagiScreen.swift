import SwiftUI
import GameCore

/// 알까기 한 판. 튕기는 화면은 Task 4가 채운다 — 지금은 판을 열고 메뉴로 돌아오는 길만 있다.
struct AlkkagiScreen: View {
    let match: OnlineMatch<Alkkagi>
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            WoodBackground()
            VStack {
                HStack {
                    Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                        .accessibilityIdentifier("header.menu")
                    Spacer()
                    Text("알까기").foregroundStyle(theme.ivory)
                    Spacer()
                }.padding(16)
                Spacer()
            }
        }
    }
}
