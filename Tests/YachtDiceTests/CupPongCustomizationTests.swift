import Testing
import UIKit
@testable import YachtDice

@Suite("컵퐁 사진 저장")
@MainActor
struct CupPongCustomizationTests {
    @Test("사진을 정사각형으로 저장하고 컵별로 복원·삭제한다")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CupPongCustomizationStore(directory: directory)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 600)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
        }
        try store.setImage(data: #require(photo.pngData()), for: 3)
        let restored = CupPongCustomizationStore(directory: directory)
        #expect(restored.image(for: 3)?.size == CGSize(width: 512, height: 512))
        #expect(restored.image(for: 2) == nil)
        #expect(throws: (any Error).self) { try restored.setImage(data: Data([1, 2, 3]), for: 3) }
        #expect(restored.image(for: 3) != nil)
        #expect(throws: (any Error).self) { try restored.setImage(data: #require(photo.pngData()), for: 10) }
        try restored.removeImage(for: 3)
        #expect(CupPongCustomizationStore(directory: directory).image(for: 3) == nil)
    }

    @Test("저장 실패는 화면의 기존 사진을 덮지 않는다")
    func failedWrite() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CupPongCustomizationStore(directory: file)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        #expect(throws: (any Error).self) { try store.setImage(data: #require(photo.pngData()), for: 0) }
        #expect(store.image(for: 0) == nil)
        #expect(store.revision == 0)
    }
}
