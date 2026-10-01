import UIKit

internal struct ReadCursor: Encodable, Equatable {
    let conversationId: String
    let throughSeq: Int64
}

internal enum ReadTarget {
    case bounded(ReadCursor)
    case legacy
}

extension ChatModel {
    func reloadAfterStaleGet() {
        guard reloadTask == nil else { return }
        // MainActor runs this after the rejected fetch's defer releases loading.
        reloadTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.reloadTask = nil
            guard self.current, self.isVisible, UIApplication.shared.applicationState == .active else { return }
            await self.load()
        }
    }

    // Only processed GET messages establish a read boundary; send acknowledgments never do.
    func processedReadTarget(conversationId: String?, hasConversation: Bool,
                             boundedRead: Bool?, messages: [Message]) throws -> ReadTarget? {
        guard hasConversation else {
            readCursor = nil
            maxSeq = 0
            session?.store.cursor = 0
            return nil
        }
        guard boundedRead == true else {
            readCursor = nil
            return .legacy
        }
        guard let conversationId, !conversationId.isEmpty,
              messages.allSatisfy({ ($0.seq ?? -1) > 0 && ($0.seq ?? -1) <= 9_007_199_254_740_991 }) else {
            throw ReceptionAPIError(code: "invalid_response", status: 0)
        }
        let previous = readCursor?.conversationId == conversationId ? readCursor?.throughSeq ?? 0 : 0
        let cursor = ReadCursor(conversationId: conversationId,
                                throughSeq: max(previous, messages.compactMap(\.seq).max() ?? 0))
        readCursor = cursor
        maxSeq = cursor.throughSeq
        session?.store.cursor = maxSeq
        return .bounded(cursor)
    }

    func markRead(target: ReadTarget?) async throws {
        guard let session, let target, canApplyRead else { return }
        let generation = Reception.shared.invalidateRead()
        let count: Int
        switch target {
        case .bounded(let cursor):
            struct Response: Decodable {
                let conversationId: String
                let readSeq: Int64
                let unreadCount: Int
            }
            let response: Response = try await session.api.request("conversation/read", method: "POST", authenticated: true,
                body: ReceptionAPI.encode(cursor))
            guard response.conversationId == cursor.conversationId,
                  response.readSeq >= cursor.throughSeq, response.readSeq <= 9_007_199_254_740_991,
                  response.unreadCount >= 0 else { throw ReceptionAPIError(code: "invalid_response", status: 0) }
            guard readCursor == cursor else { return }
            count = response.unreadCount
        case .legacy:
            // Older servers ignore read bodies. Preserve their explicit unbounded contract.
            let _: EmptyResponse = try await session.api.request("conversation/read", method: "POST", authenticated: true)
            guard canApplyRead, generation == Reception.shared.readGeneration else { return }
            struct Response: Decodable { let unreadCount: Int }
            let response: Response = try await session.api.request("conversation/unread", authenticated: true)
            guard response.unreadCount >= 0 else { throw ReceptionAPIError(code: "invalid_response", status: 0) }
            count = response.unreadCount
        }
        guard canApplyRead else { return }
        Reception.shared.noteRead(count, generation: generation)
    }

    private var canApplyRead: Bool {
        current && isVisible && !Task.isCancelled && UIApplication.shared.applicationState == .active
    }
}
