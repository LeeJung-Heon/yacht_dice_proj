import Foundation
import Supabase
import GameCore

/// 사진은 별도 행으로 공유한다. RLS가 나와 실제 컵퐁 대전 상대에게만 읽기를 허용한다.
@MainActor
struct CupPongPhotoService {
    let service: SupabaseService

    struct Design: Codable, Equatable, Sendable {
        let ownerUID: UUID
        let images: [String: String]
        let revision: UUID
        enum CodingKeys: String, CodingKey {
            case ownerUID = "owner_uid", images, revision
        }
    }

    func publish(_ store: CupPongCustomizationStore) async throws {
        if service.uid == nil { await service.signIn() }
        guard let uid = service.uid else { throw SupabaseService.ServiceError.notSignedIn }
        var images: [String: String] = [:]
        for index in 0..<CupPong.cupCount {
            if let data = store.image(for: index)?.jpegData(compressionQuality: 0.85) {
                images[String(index)] = data.base64EncodedString()
            }
        }
        let design = Design(ownerUID: uid, images: images, revision: UUID())
        try await service.client.from("cuppong_designs").upsert(design).execute()
    }

    func fetch(owner: UUID) async throws -> Design? {
        let rows: [Design] = try await service.client.from("cuppong_designs").select()
            .eq("owner_uid", value: owner.uuidString).limit(1).execute().value
        return rows.first
    }

    /// 바뀌지 않은 사진을 매번 다운로드하지 않는다.
    func revision(owner: UUID) async throws -> UUID? {
        struct Revision: Decodable { let revision: UUID }
        let rows: [Revision] = try await service.client.from("cuppong_designs").select("revision")
            .eq("owner_uid", value: owner.uuidString).limit(1).execute().value
        return rows.first?.revision
    }

    func load(_ design: Design) throws -> CupPongCustomizationStore {
        let store = CupPongCustomizationStore()
        for (key, encoded) in design.images {
            guard let index = Int(key), (0..<CupPong.cupCount).contains(index), encoded.count <= 350_000,
                  let data = Data(base64Encoded: encoded) else { throw CupPongCustomizationStore.PhotoError.invalidImage }
            try store.setImage(data: data, for: index)
        }
        return store
    }
}
