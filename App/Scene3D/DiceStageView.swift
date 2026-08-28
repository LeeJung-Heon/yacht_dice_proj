import SwiftUI
import RealityKit

struct DiceStageView: View {
    let stage: DiceStage

    var body: some View {
        RealityView { content in
            stage.attach(to: content)
        }
        .accessibilityHidden(true)   // 주사위 값은 ActionBar가 음성으로 읽는다
    }
}
