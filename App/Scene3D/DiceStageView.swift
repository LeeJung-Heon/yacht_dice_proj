import SwiftUI
import RealityKit

struct DiceStageView: View {
    let stage: DiceStage
    /// 트레이 안 주사위를 탭했을 때. 슬롯 번호를 준다.
    var onDieTapped: (Int) -> Void = { _ in }

    var body: some View {
        RealityView { content in
            stage.attach(to: content)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let slot = DiceSceneBuilder.slot(of: value.entity) { onDieTapped(slot) }
                }
        )
        .accessibilityHidden(true)   // 주사위 값은 ActionBar가 음성으로 읽는다
    }
}
