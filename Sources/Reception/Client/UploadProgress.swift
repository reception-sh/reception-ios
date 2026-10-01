import Foundation

internal final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let update: @MainActor @Sendable (Double) -> Void
    init(update: @escaping @MainActor @Sendable (Double) -> Void) { self.update = update }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        Task { @MainActor in update(fraction) }
    }
}
