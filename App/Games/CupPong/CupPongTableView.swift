import SwiftUI
import RealityKit

struct CupPongTableView: View {
    let cups: [Bool]
    let owner: String
    let ball: (x: Int, y: Int, height: CGFloat)?
    let vanishing: Int?
    var customization: CupPongCustomizationStore = .shared
    var focusedCup: Int?
    @State private var scene: CupPongScene?

    var body: some View {
        let _ = customization.revision
        RealityView { content in
            let stage = CupPongScene()
            content.add(stage.root)
            content.add(stage.camera)
            stage.focus(on: focusedCup)
            stage.update(cups: cups, ball: ball, vanishing: vanishing, customization: customization)
            scene = stage
        } update: { _ in
            scene?.focus(on: focusedCup)
            scene?.update(cups: cups, ball: ball, vanishing: vanishing, customization: customization)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D 컵퐁 테이블, \(owner) \(cups.filter { $0 }.count)개")
        .accessibilityIdentifier("cuppong.table")
    }
}
