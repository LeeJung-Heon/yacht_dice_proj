import Testing
import RealityKit
import UIKit
import GameCore
@testable import YachtDice

@Suite("컵퐁 3D 씬")
@MainActor
struct CupPongSceneTests {
    @Test("비운 컵만 사라지고 공은 규칙 착지점으로 이동한다")
    func stateRendering() throws {
        let scene = CupPongScene()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CupPongCustomizationStore(directory: directory)
        var cups = Array(repeating: true, count: 10)
        cups[4] = false
        scene.update(cups: cups, ball: (200, 2400, 350), vanishing: nil, customization: store)
        #expect(scene.root.findEntity(named: "cup.4")?.isEnabled == false)
        #expect(scene.root.findEntity(named: "cup.3")?.isEnabled == true)
        let ball = try #require(scene.root.findEntity(named: "ball"))
        #expect(abs(ball.position.y - 0.14) < 0.0001)
        #expect(abs(ball.position.x - 0.08) < 0.0001)
        #expect(abs(ball.position.z + 0.96) < 0.0001)
        let front = try #require(scene.root.findEntity(named: "cup.9"))
        #expect(abs(front.position.z + 0.88) < 0.0001)
        scene.update(cups: cups, ball: nil, vanishing: 3, customization: store)
        #expect(!ball.isEnabled)
        #expect(scene.root.findEntity(named: "cup.3")?.isEnabled == false)
    }

    @Test("사진을 선택한 컵만 이미지가 붙고 삭제하면 기본 디자인으로 돌아간다")
    func photoRendering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CupPongCustomizationStore(directory: directory)
        let scene = CupPongScene()
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        try store.setImage(data: #require(photo.pngData()), for: 2)
        scene.update(cups: Array(repeating: true, count: 10), ball: nil, vanishing: nil, customization: store)
        let label = try #require(scene.root.findEntity(named: "photo.2") as? ModelEntity)
        #expect(label.isEnabled)
        let material = try #require(label.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(material.baseColor.texture != nil)
        #expect(scene.root.findEntity(named: "photo.1")?.isEnabled == false)
        try store.removeImage(for: 2)
        scene.update(cups: Array(repeating: true, count: 10), ball: nil, vanishing: nil, customization: store)
        #expect(!label.isEnabled)
    }
}
