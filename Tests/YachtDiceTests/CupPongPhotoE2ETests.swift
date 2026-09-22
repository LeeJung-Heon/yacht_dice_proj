import Testing
import Foundation
import UIKit
import Supabase
import GameCore
@testable import YachtDice

@Suite("컵퐁 사진 공유 통합", .enabled(if: ProcessInfo.processInfo.environment["YACHT_SUPABASE_E2E"] == "1"))
@MainActor
struct CupPongPhotoE2ETests {
    private func makeClient() -> SupabaseClient {
        SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.publishableKey,
                       options: .init(auth: .init(storage: SupabaseE2ETests.MemoryStorage())))
    }

    @Test("컵 사진은 대전 상대에게 전달되고 타인은 읽거나 덮지 못한다")
    func 컵_사진_공유() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        let stranger = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn(); await stranger.signIn()
        let uid = try #require(host.uid)
        let store = CupPongCustomizationStore()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        try store.setImage(data: #require(image.pngData()), for: 7)
        let hostPhotos = CupPongPhotoService(service: host)
        var roomID: UUID?
        do {
            try await hostPhotos.publish(store)
            let guestPhotos = CupPongPhotoService(service: guest)
            #expect(try await guestPhotos.fetch(owner: uid) == nil)
            let room = try await host.createRoom(name: "사진 호스트", game: "cuppong")
            roomID = room.id
            let joined = try await guest.joinRoom(code: room.code, name: "사진 게스트", game: "cuppong")
            #expect(try MoveLog<CupPong>.decoded(from: joined.log).state == CupPong.initial())
            let rawLog = try #require(JSONSerialization.jsonObject(with: joined.log) as? [String: Any])
            #expect(rawLog["rulesVersion"] as? Int == 2)
            let received = try #require(try await guestPhotos.fetch(owner: uid))
            #expect(received.images.keys.sorted() == ["7"])
            let encoded = try #require(received.images["7"])
            let decoded = try #require(Data(base64Encoded: encoded))
            #expect(UIImage(data: decoded)?.size == CGSize(width: 512, height: 512))
            #expect(try await CupPongPhotoService(service: stranger).fetch(owner: uid) == nil)
            do {
                try await stranger.client.from("cuppong_designs").upsert(received).execute()
                Issue.record("다른 계정이 사진을 덮었다")
            } catch { }
            try store.removeImage(for: 7)
            try await hostPhotos.publish(store)
            #expect(try await guestPhotos.fetch(owner: uid)?.images.isEmpty == true)
            try await host.deleteMatch(id: room.id)
            try await host.client.from("cuppong_designs").delete().eq("owner_uid", value: uid.uuidString).execute()
        } catch {
            if let roomID { try? await host.deleteMatch(id: roomID) }
            try? await host.client.from("cuppong_designs").delete().eq("owner_uid", value: uid.uuidString).execute()
            throw error
        }
    }

}
