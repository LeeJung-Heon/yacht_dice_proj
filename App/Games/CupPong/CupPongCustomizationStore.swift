import Foundation
import Observation
import UIKit
import ImageIO
import GameCore

/// 사진은 대전 로그와 분리한다. 디스크에 쓰인 뒤에만 화면을 갱신한다.
@MainActor @Observable
final class CupPongCustomizationStore {
    static let shared = CupPongCustomizationStore(directory:
        URL.applicationSupportDirectory.appendingPathComponent("CupPongPhotos", isDirectory: true))
    private let directory: URL?
    private var images: [Int: UIImage] = [:]
    private(set) var revision = 0

    enum PhotoError: LocalizedError {
        case invalidImage, invalidCup
        var errorDescription: String? {
            switch self {
            case .invalidImage: "사진을 읽을 수 없습니다. 다른 사진을 선택해 주세요."
            case .invalidCup: "선택한 컵을 찾을 수 없습니다."
            }
        }
    }

    /// directory가 nil이면 상대 사진을 보관하는 메모리 캐시다.
    init(directory: URL? = nil) {
        self.directory = directory
        guard let directory else { return }
        for cup in 0..<CupPong.cupCount {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("cup-\(cup).jpg")), let image = UIImage(data: data) {
                images[cup] = image
            }
        }
    }

    func image(for cup: Int) -> UIImage? { images[cup] }

    func setImage(data: Data, for cup: Int) throws {
        guard (0..<CupPong.cupCount).contains(cup) else { throw PhotoError.invalidCup }
        // 전체 원본 대신 썸네일을 디코드한다. EXIF 방향을 반영하고 메타데이터 없이 다시 저장한다.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw PhotoError.invalidImage }
        let image = UIImage(cgImage: thumbnail)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            let scale = 512 / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (512 - size.width) / 2, y: (512 - size.height) / 2, width: size.width, height: size.height))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { throw PhotoError.invalidImage }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: directory.appendingPathComponent("cup-\(cup).jpg"), options: .atomic)
        }
        images[cup] = square
        revision += 1
    }

    func removeImage(for cup: Int) throws {
        guard (0..<CupPong.cupCount).contains(cup) else { throw PhotoError.invalidCup }
        if let directory {
            let url = directory.appendingPathComponent("cup-\(cup).jpg")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        images[cup] = nil
        revision += 1
    }
}
