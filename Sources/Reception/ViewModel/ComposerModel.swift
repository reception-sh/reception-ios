import SwiftUI
import PhotosUI
import Observation
import ImageIO

@MainActor @Observable
internal final class ComposerModel {
    struct Photo: Identifiable { let id = UUID(); let image: UIImage }
    private let store: DeviceStore?
    var text = "" { didSet { store?.draftText = text; onTextChange?(text) } }
    var onTextChange: ((String) -> Void)?
    init(store: DeviceStore? = nil) {
        self.store = store
        text = store?.draftText ?? ""
    }
    var selection: [PhotosPickerItem] = []
    var photos: [Photo] = []
    var loading = false
    var hasPhotoError = false
    var error: String? { hasPhotoError ? Theme.string("Could not load this photo.") : nil }
    var canSend: Bool {
        !loading && photos.count <= 5 && text.utf16.count <= 4000 && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty)
    }
    func loadSelection() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; selection = [] }
        for item in selection.prefix(max(0, 5 - photos.count)) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                      ] as CFDictionary) else {
                    hasPhotoError = true; continue
                }
                photos.append(Photo(image: UIImage(cgImage: image)))
            } catch { self.hasPhotoError = true }
        }
    }
    func remove(_ id: UUID) { photos.removeAll { $0.id == id } }
    func send(to chat: ChatModel) {
        // During a cooldown the draft and its photos stay here untouched.
        guard canSend, chat.canSend, chat.cooldownAllowsSend(photos: !photos.isEmpty) else { return }
        chat.send(text: text, images: photos.map(\.image))
        text = ""; photos = []; hasPhotoError = false
    }
}
