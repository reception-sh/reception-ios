import CryptoKit
import Foundation

/// Small, session-scoped snapshots without signed download URLs; excluded from backups.
@MainActor
internal final class TeamProfileCache {
    struct Entry: Codable, Equatable {
        var name: String?
        var photoId: String?
        var data: Data?
    }
    private let file: URL?
    private var entries: [String: Entry] = [:]
    private var acceptsWrites = true

    init(scope: String) {
        let name = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.reception.sdk", isDirectory: true).appendingPathComponent(name + "-photos.json")
    }

    func load() -> [String: Entry] {
        guard let file,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 9 * 1024 * 1024,
              let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data), decoded.count <= 50 else { return [:] }
        entries = decoded
        return entries
    }

    func save(_ data: Data, photoId: String, memberId: String) {
        guard acceptsWrites, data.count <= 512 * 1024,
              entries.filter({ $0.key != memberId }).values.reduce(data.count, { $0 + ($1.data?.count ?? 0) }) <= 6 * 1024 * 1024,
              entries[memberId] != nil || entries.count < 50 else { return }
        entries[memberId] = Entry(name: entries[memberId]?.name, photoId: photoId, data: data)
        persist()
    }

    func update(_ team: [String: TeamMember], showsPhotos: Bool) {
        guard acceptsWrites else { return }
        var updated: [String: Entry] = [:]
        for id in team.keys.sorted().prefix(50) {
            guard let member = team[id] else { continue }
            let photo = showsPhotos && member.photoId != nil ? entries[id] : nil
            updated[id] = Entry(name: member.name, photoId: photo?.photoId, data: photo?.data)
        }
        guard updated != entries else { return }
        entries = updated
        persist()
    }

    func clear() {
        // A late download from the discarded session cannot recreate deleted files.
        acceptsWrites = false
        entries.removeAll()
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    private func persist() {
        guard let file else { return }
        if entries.isEmpty { try? FileManager.default.removeItem(at: file); return }
        do {
            var directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Disk availability must not prevent displaying the downloaded photo.
        }
    }
}
