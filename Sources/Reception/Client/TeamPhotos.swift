import UIKit
import Observation

/// Shows cached photos immediately, then refreshes them from authoritative team details.
@MainActor @Observable
internal final class TeamPhotos {
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var loadedKeys: [String: String] = [:]
    private struct Pending: Sendable {
        let key: String
        let url: URL
        let id: UUID
        let task: Task<Void, Never>
    }
    @ObservationIgnored private var pending: [String: Pending] = [:]
    private let session: URLSession
    private let cache: TeamPhotoCache?

    init(session: URLSession = .shared, cache: TeamPhotoCache? = nil) {
        self.session = session
        self.cache = cache
        for (id, entry) in cache?.load() ?? [:] {
            if let image = UIImage(data: entry.data) {
                images[id] = image
                loadedKeys[id] = entry.photoId
            }
        }
    }

    deinit { for request in pending.values { request.task.cancel() } }

    func update(_ team: [String: TeamMember]) {
        cache?.retain(Set(team.values.filter { $0.photoId != nil }.map(\.id)))
        for id in Set(images.keys).union(pending.keys) where team[id]?.photoId == nil && team[id]?.photoUrl == nil {
            pending.removeValue(forKey: id)?.task.cancel()
            images[id] = nil
            loadedKeys[id] = nil
        }
        for (id, member) in team {
            guard let url = member.photoUrl else { continue }
            // Older servers have no photo ID; the full URL remains a safe fallback.
            let key = member.photoId ?? url.absoluteString
            if loadedKeys[id] == key {
                pending.removeValue(forKey: id)?.task.cancel()
                continue
            }
            if pending[id]?.key == key, pending[id]?.url == url { continue }
            pending.removeValue(forKey: id)?.task.cancel()
            let attempt = UUID()
            let session = session
            let task = Task { [weak self] in
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 30
                    let (data, response) = try await session.data(for: request)
                    try Task.checkCancellation()
                    guard let self, self.pending[id]?.id == attempt else { return }
                    defer { self.pending[id] = nil }
                    guard let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode),
                          let image = UIImage(data: data) else { return }
                    self.images[id] = image
                    self.loadedKeys[id] = key
                    if let photoId = member.photoId { self.cache?.save(data, photoId: photoId, memberId: id) }
                } catch {
                    if self?.pending[id]?.id == attempt { self?.pending[id] = nil }
                }
            }
            // Keep the previous photo visible until its replacement has loaded successfully.
            pending[id] = Pending(key: key, url: url, id: attempt, task: task)
        }
    }
}
