import UIKit
import XCTest
@testable import Reception

@MainActor
final class TeamProfilesTests: XCTestCase {
    private func member(_ photo: String?, link: String = "first") throws -> TeamMember {
        TeamMember(id: "agent", name: "Alex", photoUrl: photo == nil ? nil : try XCTUnwrap(URL(string: "https://reception.test/\(link)")), photoId: photo)
    }

    private func imageData(_ color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Photo request did not settle")
    }

    func testReusesPhotoAcrossSignedLinksAndKeepsItUntilReplacementLoads() async throws {
        let red = try imageData(.red), blue = try imageData(.blue)
        let gate = StubURLProtocol.Gate()
        StubURLProtocol.install { request in
            .init(data: request.path == "/changed" ? blue : red, gate: request.path == "/changed" ? gate : nil)
        }
        defer { gate.release(); StubURLProtocol.uninstall() }
        let photos = TeamProfiles()
        photos.update(["agent": try member("photo-1")])
        try await waitUntil { photos.images["agent"] != nil }
        let original = try XCTUnwrap(photos.images["agent"])
        photos.update(["agent": TeamMember(id: "agent", name: "Alex", photoUrl: nil, photoId: "photo-1")])
        XCTAssertTrue(photos.images["agent"] === original)
        photos.update(["agent": try member("photo-1", link: "renewed-signature")])
        XCTAssertTrue(photos.images["agent"] === original)
        photos.update(["agent": try member("photo-2", link: "changed")])
        try await waitUntil { StubURLProtocol.requests.count == 2 }
        XCTAssertTrue(photos.images["agent"] === original)
        gate.release()
        try await waitUntil { photos.images["agent"] !== original }
        XCTAssertNotNil(photos.images["agent"])
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/first", "/changed"])
    }

    func testRemovalCancelsPendingReplacementAndCannotRestoreOldPhoto() async throws {
        let data = try imageData(.red)
        let gate = StubURLProtocol.Gate()
        StubURLProtocol.install { request in .init(data: data, gate: request.path == "/changed" ? gate : nil) }
        defer { gate.release(); StubURLProtocol.uninstall() }
        let photos = TeamProfiles()
        photos.update(["agent": try member("photo-1")])
        try await waitUntil { photos.images["agent"] != nil }
        photos.update(["agent": try member("photo-2", link: "changed")])
        try await waitUntil { StubURLProtocol.requests.count == 2 }
        photos.update(["agent": try member(nil)])
        XCTAssertTrue(photos.images.isEmpty)
        gate.release()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(photos.images.isEmpty)
        photos.update(["agent": try member("photo-3")])
        try await waitUntil { photos.images["agent"] != nil }
        photos.update([:])
        XCTAssertTrue(photos.images.isEmpty)
    }

    func testExpiredLinkRetriesWithRefreshedLinkAndLegacyPayloadDecodes() async throws {
        let data = try imageData(.red)
        StubURLProtocol.install { request in .init(status: request.path == "/expired" ? 403 : 200, data: data) }
        defer { StubURLProtocol.uninstall() }
        let photos = TeamProfiles()
        photos.update(["agent": try member("photo-1", link: "expired")])
        try await waitUntil { StubURLProtocol.requests.count == 1 }
        XCTAssertTrue(photos.images.isEmpty)
        photos.update(["agent": try member("photo-1", link: "refreshed")])
        try await waitUntil { photos.images["agent"] != nil }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        let legacy = try JSONDecoder().decode(TeamMember.self, from: Data(#"{"id":"agent","name":"Alex","photoUrl":null}"#.utf8))
        XCTAssertNil(legacy.photoId)
        let current = try JSONDecoder().decode(TeamMember.self, from: Data(#"{"id":"agent","name":"Alex","photoUrl":null,"photoId":"photo-1"}"#.utf8))
        XCTAssertEqual(current.photoId, "photo-1")
    }

    func testDiskCacheRestoresWithoutNetworkAndRemovalPersists() async throws {
        let scope = UUID().uuidString
        let cache = TeamProfileCache(scope: scope)
        defer { cache.clear(); StubURLProtocol.uninstall() }
        let data = try imageData(.red)
        StubURLProtocol.install { _ in .init(data: data) }
        let photos = TeamProfiles(cache: cache)
        photos.update(["agent": try member("photo-1")])
        try await waitUntil { photos.images["agent"] != nil }
        let restored = TeamProfiles(cache: TeamProfileCache(scope: scope))
        XCTAssertEqual(restored.members["agent"]?.name, "Alex")
        XCTAssertNotNil(restored.images["agent"], "Restoration must be synchronous, before any team response")
        restored.update(["agent": try member("photo-1", link: "new-signature")])
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertTrue(TeamProfiles(cache: TeamProfileCache(scope: UUID().uuidString)).images.isEmpty)
        restored.update(["agent": try member(nil)])
        XCTAssertTrue(TeamProfiles(cache: TeamProfileCache(scope: scope)).images.isEmpty)
    }

    func testClearedStoreRejectsLateDownloadWrites() async throws {
        let scope = UUID().uuidString
        let store = DeviceStore(scope: scope, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let data = try imageData(.blue)
        let gate = StubURLProtocol.Gate()
        StubURLProtocol.install { _ in .init(data: data, gate: gate) }
        defer { gate.release(); store.clear(); StubURLProtocol.uninstall() }
        let photos = TeamProfiles(cache: store.teamProfileCache)
        photos.update(["agent": try member("photo-1")])
        try await waitUntil { StubURLProtocol.requests.count == 1 }
        store.clear()
        gate.release()
        try await waitUntil { photos.images["agent"] != nil }
        XCTAssertTrue(TeamProfileCache(scope: scope).load().isEmpty)
    }


    func testNamesRestoreWithoutPhotosAndRefreshWithoutStaleMembers() throws {
        let scope = UUID().uuidString
        let cache = TeamProfileCache(scope: scope)
        defer { cache.clear() }
        let profiles = TeamProfiles(cache: cache)
        profiles.update(["agent": try member(nil)], showsPhotos: false)
        let restored = TeamProfiles(cache: TeamProfileCache(scope: scope))
        XCTAssertEqual(restored.members["agent"]?.name, "Alex")
        XCTAssertTrue(restored.images.isEmpty)
        restored.update(["agent": TeamMember(id: "agent", name: "Sam", photoUrl: nil)], showsPhotos: false)
        XCTAssertEqual(TeamProfiles(cache: TeamProfileCache(scope: scope)).members["agent"]?.name, "Sam")
        restored.update([:])
        XCTAssertTrue(restored.members.isEmpty)
        XCTAssertTrue(TeamProfiles(cache: TeamProfileCache(scope: scope)).members.isEmpty)
    }

}
