import UIKit
import Observation

/// Restores names and photos together, then refreshes them from authoritative team details.
@MainActor @Observable
internal final class TeamProfiles {
    private(set) var members: [String: TeamMember] = [:]
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
    private let cache: TeamProfileCache?

    init(session: URLSession = .shared, cache: TeamProfileCache? = nil) {
        self.session = session
        self.cache = cache
        for (id, entry) in cache?.load() ?? [:] {
            if let name = entry.name {
                members[id] = TeamMember(id: id, name: name, photoUrl: nil, photoId: entry.photoId)
            }
            if let data = entry.data, let image = UIImage(data: data) {
                images[id] = image
                loadedKeys[id] = entry.photoId
            }
        }
    }

    deinit { for request in pending.values { request.task.cancel() } }

    func update(_ team: [String: TeamMember], showsPhotos: Bool = true) {
        members = team
        cache?.update(team, showsPhotos: showsPhotos)
        let photos = showsPhotos ? team : [:]
        for id in Set(images.keys).union(pending.keys) where photos[id]?.photoId == nil && photos[id]?.photoUrl == nil {
            pending.removeValue(forKey: id)?.task.cancel()
            images[id] = nil
            loadedKeys[id] = nil
        }
        for (id, member) in photos {
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
