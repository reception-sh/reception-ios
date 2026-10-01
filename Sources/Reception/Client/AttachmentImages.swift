import Foundation

@MainActor
internal final class AttachmentImages {
    private struct Entry { weak var loader: AttachmentImageLoader? }
    private var entries: [String: Entry] = [:]

    func loader(for attachment: Attachment, session: DeviceSession) -> AttachmentImageLoader {
        // Views own images. Keep only live entries, without a second history or image cache.
        entries = entries.filter { $0.value.loader != nil }
        if let loader = entries[attachment.id]?.loader { return loader }
        let loader = AttachmentImageLoader(attachment: attachment, session: session)
        entries[attachment.id] = Entry(loader: loader)
        return loader
    }

    func invalidate() {
        for entry in entries.values { entry.loader?.invalidate() }
        entries.removeAll()
    }
}
