import UIKit
import Observation

@MainActor @Observable
internal final class AttachmentImageLoader {
    private(set) var image: UIImage?
    private(set) var failed = false
    private(set) var loading = false
    private var attachment: Attachment
    private weak var session: DeviceSession?
    private var task: Task<Void, Never>?
    private var attempt = UUID()
    private var readers = 0

    init(attachment: Attachment, session: DeviceSession) {
        self.attachment = attachment
        self.session = session
    }

    private var current: Bool {
        guard let session else { return false }
        return session === Reception.shared.session && !session.invalidated
    }

    func appear() {
        readers += 1
        if image == nil && !failed { load(refresh: false) }
    }

    func disappear() {
        readers = max(0, readers - 1)
        if readers == 0 { cancel() }
    }

    func retry() { load(refresh: true) }

    func invalidate() {
        cancel()
        image = nil
        failed = false
    }

    private func cancel() {
        attempt = UUID()
        task?.cancel()
        task = nil
        loading = false
    }

    private func load(refresh: Bool) {
        guard current, task == nil else { return }
        let id = UUID()
        attempt = id
        failed = false
        loading = true
        task = Task {
            defer {
                if attempt == id { task = nil; loading = false }
            }
            do {
                if refresh { try await resolve() }
                let data: Data
                do { data = try await Self.download(attachment.url) }
                catch ImageDownloadError.forbidden where !refresh {
                    try checkCurrent()
                    try await resolve()
                    data = try await Self.download(attachment.url)
                }
                try checkCurrent()
                guard attempt == id else { return }
                guard let decoded = UIImage(data: data) else { throw ImageDownloadError.invalidImage }
                image = decoded
            } catch {
                guard current, !Task.isCancelled, attempt == id else { return }
                failed = true
            }
        }
    }

    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard current else { throw CancellationError() }
    }

    private func resolve() async throws {
        try checkCurrent()
        guard let session, session.isRegistered else { throw CancellationError() }
        // Treat the ID as one path component, never as a caller-supplied endpoint/query.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard let id = attachment.id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw ImageDownloadError.invalidImage
        }
        do {
            let resolved: Attachment = try await session.api.request("attachments/\(id)", authenticated: true)
            try checkCurrent()
            guard resolved.id == attachment.id else { throw ImageDownloadError.invalidImage }
            attachment = resolved
        } catch {
            try checkCurrent()
            // Only resolver errors carry device authentication. Storage errors never reset support.
            _ = Reception.shared.chatModel().handleReset(error)
            throw error
        }
    }

    private nonisolated static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ImageDownloadError.invalidImage }
        ReceptionAPI.logRateLimit(response)
        if response.statusCode == 403 { throw ImageDownloadError.forbidden }
        guard (200..<300).contains(response.statusCode) else { throw ImageDownloadError.unavailable }
        return data
    }

    private enum ImageDownloadError: Error { case forbidden, unavailable, invalidImage }
}
