import CryptoKit
import Foundation
import UIKit

/// A per-session snapshot; pending messages keep their client IDs across launches.
@MainActor
internal final class ChatCache {
    private let file: URL?
    private var hasLoadedLatestMessageAt = false
    private var cachedLatestMessageAt: Date?
    private var encodedImages: [String: [Data]] = [:]

    init(scope: String) {
        let name = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.reception.sdk", isDirectory: true).appendingPathComponent(name + ".json")
    }

    var latestMessageAt: Date? {
        if !hasLoadedLatestMessageAt {
            rememberLatestMessageAt(in: readSnapshots())
        }
        return cachedLatestMessageAt
    }

    private func readSnapshots() -> [Snapshot] {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshots = try? JSONDecoder().decode([Snapshot].self, from: data) else { return [] }
        return snapshots
    }

    private func rememberLatestMessageAt(in snapshots: [Snapshot]) {
        cachedLatestMessageAt = snapshots.map(\.createdAt).max()
        hasLoadedLatestMessageAt = true
    }

    func load() -> [Message] {
        let snapshots = readSnapshots()
        rememberLatestMessageAt(in: snapshots)
        encodedImages.removeAll()
        for snapshot in snapshots where !snapshot.hasConfirmedAttachments {
            encodedImages[snapshot.id] = snapshot.images
        }
        return snapshots.map { $0.message }
    }

    func save(_ messages: [Message]) {
        guard let file else { return }
        let recent = Set(messages.filter { $0.seq != nil }.suffix(50).map(\.id))
        do {
            let retained = messages.filter { $0.seq == nil || recent.contains($0.id) }
            let ids = Set(retained.map(\.id))
            encodedImages = encodedImages.filter { ids.contains($0.key) }
            let snapshots = try retained.map { message in
                let images: [Data]
                if message.hasConfirmedAttachments || message.images.isEmpty { images = []; encodedImages[message.id] = nil }
                else if let cached = encodedImages[message.id] { images = cached }
                else {
                    images = try message.images.map { image in
                        guard let data = image.jpegData(compressionQuality: 0.85) else {
                            throw ReceptionAPIError(code: "invalid_image", status: 0)
                        }
                        return data
                    }
                    encodedImages[message.id] = images
                }
                return Snapshot(message, images: images)
            }
            var directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(snapshots).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            rememberLatestMessageAt(in: snapshots)
        } catch {
            // Disk availability must never prevent sending a support message.
        }
    }

    func clear() {
        rememberLatestMessageAt(in: [])
        encodedImages.removeAll()
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private struct Snapshot: Codable {
        let id: String
        let seq: Int64?
        let sender: String
        let text: String
        let kind: String?
        let reviewUrl: URL?
        let paywallId: String?
        let paywallTitle: String?
        let buttonLabel: String?
        let authorId: String?
        let actionClickedAt: Date?
        let createdAt: Date
        let failed: Bool
        /// Missing in older snapshots, which never needed a manual retry.
        let awaitsManualRetry: Bool?
        let retryAfterLimitRelease: Bool?
        let retryAfterTransientFailure: Bool?
        let attachments: [Attachment]
        let images: [Data]
        let attachmentIds: [String]
        let expectedImageCount: Int?

        var hasConfirmedAttachments: Bool { seq != nil && !attachments.isEmpty }

        init(_ message: Message, images: [Data]) {
            id = message.id; seq = message.seq; sender = message.sender; text = message.text
            createdAt = message.createdAt; failed = message.status == .failed
            awaitsManualRetry = message.awaitsManualRetry
            retryAfterLimitRelease = message.retryAfterLimitRelease
            retryAfterTransientFailure = message.retryAfterTransientFailure
            attachments = message.attachments
            attachmentIds = message.hasConfirmedAttachments ? [] : message.attachmentIds
            paywallId = message.paywallId; paywallTitle = message.paywallTitle; buttonLabel = message.buttonLabel
            authorId = message.authorId
            actionClickedAt = message.actionClickedAt
            kind = message.kind; reviewUrl = message.reviewUrl
            self.images = images
            expectedImageCount = message.expectedImageCount ?? message.images.count
        }

        var message: Message {
            Message(id: id, seq: seq, sender: sender, text: text, attachments: attachments,
                    createdAt: createdAt, kind: kind ?? "TEXT", reviewUrl: reviewUrl,
                    paywallId: paywallId, paywallTitle: paywallTitle, buttonLabel: buttonLabel, authorId: authorId, actionClickedAt: actionClickedAt, status: seq != nil ? .sent : failed ? .failed : .sending,
                    awaitsManualRetry: seq == nil && awaitsManualRetry == true,
                    retryAfterLimitRelease: seq == nil && retryAfterLimitRelease == true,
                    retryAfterTransientFailure: seq == nil && retryAfterTransientFailure == true,
                    images: hasConfirmedAttachments ? [] : images.compactMap { UIImage(data: $0) },
                    attachmentIds: hasConfirmedAttachments ? [] : attachmentIds,
                    expectedImageCount: expectedImageCount ?? images.count)
        }
    }
}
