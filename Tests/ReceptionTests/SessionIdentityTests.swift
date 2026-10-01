import XCTest
import os
@testable import Reception

@MainActor
final class SessionIdentityTests: XCTestCase {
    private final class Storage {
        var values: [String: String] = [:]
        var failsSave = false
        var saveAttempts = 0

        var client: DeviceStore.CredentialStorage {
            DeviceStore.CredentialStorage(
                read: { self.values[$0].map(KeychainStore.ReadResult.value) ?? .missing },
                save: { value, account in
                    self.saveAttempts += 1
                    guard !self.failsSave else { return false }
                    self.values[account] = value
                    return true
                },
                delete: { self.values.removeValue(forKey: $0); return true })
        }
    }

    private func makeSession(storage: Storage, userId: String?) throws -> DeviceSession {
        let store = DeviceStore(scope: "identity-tests-" + UUID().uuidString, credentialStorage: storage.client)
        try store.save(SessionCredentials(sessionSecret: "test-secret", verifiedUserId: userId))
        store.hasConversation = true
        store.draftText = "Keep this draft"
        store.cursor = 42
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store)
        _ = try session.storedCredentials()
        session.accessToken = "test-access-token"
        return session
    }

    func testFailedVerificationUpgradeIsRetriedBeforeUsingCachedToken() async throws {
        try await checkFailedSave(previousUserId: nil, nextUserId: "verified-user")
    }

    func testFailedVerificationRemovalIsRetriedBeforeUsingCachedToken() async throws {
        try await checkFailedSave(previousUserId: "verified-user", nextUserId: nil)
    }

    private func checkFailedSave(previousUserId: String?, nextUserId: String?) async throws {
        let storage = Storage()
        let session = try makeSession(storage: storage, userId: previousUserId)
        defer { session.invalidate() }
        storage.failsSave = true

        session.storeVerifiedUserId(nextUserId)

        XCTAssertTrue(session.credentialsUnsaved)
        XCTAssertEqual(session.credentials?.verifiedUserId, nextUserId)
        XCTAssertEqual(try session.store.loadCredentials()?.verifiedUserId, previousUserId)
        do {
            _ = try await session.token()
            XCTFail("Pending credentials must be saved before using the cached access token")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.code, "secure_storage_unavailable")
        }
        XCTAssertTrue(session.credentialsUnsaved)
        XCTAssertEqual(session.credentials?.sessionSecret, "test-secret")
        XCTAssertEqual(session.accessToken, "test-access-token")
        XCTAssertFalse(session.invalidated)
        XCTAssertNil(session.halt)
        XCTAssertTrue(session.store.hasConversation)
        XCTAssertEqual(session.store.draftText, "Keep this draft")
        XCTAssertEqual(session.store.cursor, 42)

        storage.failsSave = false
        let token = try await session.token()

        XCTAssertEqual(token, "test-access-token")
        XCTAssertFalse(session.credentialsUnsaved)
        XCTAssertEqual(storage.saveAttempts, 4)
        let relaunched = DeviceSession(api: session.api, store: session.store.renewed())
        defer { relaunched.deactivate() }
        XCTAssertEqual(try relaunched.storedCredentials(), session.credentials)
    }

    func testIdenticalResponseRetriesPendingSave() throws {
        let storage = Storage()
        let session = try makeSession(storage: storage, userId: "verified-user")
        defer { session.invalidate() }
        storage.failsSave = true
        session.storeVerifiedUserId(nil)
        session.storeVerifiedUserId(nil)
        XCTAssertTrue(session.credentialsUnsaved)
        XCTAssertEqual(try session.store.loadCredentials()?.verifiedUserId, "verified-user")

        storage.failsSave = false
        session.storeVerifiedUserId(nil)

        XCTAssertFalse(session.credentialsUnsaved)
        XCTAssertNil(try session.store.loadCredentials()?.verifiedUserId)
        XCTAssertEqual(try session.store.loadCredentials()?.sessionSecret, "test-secret")
        XCTAssertEqual(storage.saveAttempts, 4)
        session.storeVerifiedUserId(nil)
        XCTAssertEqual(storage.saveAttempts, 4, "An unchanged, persisted identity needs no further write")
    }

    func testLatestIdentityReplacesAnEarlierPendingSave() throws {
        let storage = Storage()
        let session = try makeSession(storage: storage, userId: nil)
        defer { session.invalidate() }
        storage.failsSave = true
        session.storeVerifiedUserId("verified-user")
        session.storeVerifiedUserId(nil)
        XCTAssertTrue(session.credentialsUnsaved)

        storage.failsSave = false
        try session.persistPendingCredentials()

        XCTAssertFalse(session.credentialsUnsaved)
        XCTAssertNil(try session.store.loadCredentials()?.verifiedUserId)
        XCTAssertEqual(storage.saveAttempts, 4)
        XCTAssertEqual(session.credentials?.sessionSecret, "test-secret")
        XCTAssertEqual(session.accessToken, "test-access-token")
    }

    func testByteDistinctVerifiedUserIdReplacesStoredValue() throws {
        let storage = Storage()
        let session = try makeSession(storage: storage, userId: "\u{00e9}")
        defer { session.invalidate() }

        session.storeVerifiedUserId("e\u{0301}")

        XCTAssertEqual(Array(try XCTUnwrap(session.credentials?.verifiedUserId).utf8), [0x65, 0xcc, 0x81])
        XCTAssertEqual(Array(try XCTUnwrap(session.store.loadCredentials()?.verifiedUserId).utf8), [0x65, 0xcc, 0x81])
        XCTAssertEqual(storage.saveAttempts, 2)
        session.storeVerifiedUserId("e\u{0301}")
        XCTAssertEqual(storage.saveAttempts, 2, "An identical ID needs no further write")
    }

    func testUnverifiedIdentityReportsByteDistinctConflictWithoutResetting() throws {
        let storage = Storage()
        let session = try makeSession(storage: storage, userId: "\u{00e9}")
        let reception = Reception.shared
        let previousSession = reception.session
        let previousHandler = Reception.logHandler
        let previousLevel = Reception.logLevel
        let errors = OSAllocatedUnfairLock(initialState: [String]())
        reception.session = session
        Reception.logLevel = .error
        Reception.logHandler = { level, line in
            if level == .error { errors.withLock { $0.append(line) } }
        }
        defer {
            Reception.logHandler = previousHandler
            Reception.logLevel = previousLevel
            reception.session = previousSession
            session.invalidate()
        }

        reception.identify(userId: "\u{00e9}")
        XCTAssertTrue(errors.withLock { $0.isEmpty })
        reception.identify(userId: "e\u{0301}")
        XCTAssertEqual(errors.withLock { $0 }, ["identify(userId:) does not match the verified user; call logout() when users switch"])
        XCTAssertTrue(reception.session === session)
        XCTAssertFalse(session.invalidated)
        XCTAssertEqual(session.credentials?.sessionSecret, "test-secret")
    }
}
