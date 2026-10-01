import CryptoKit
import UIKit

@MainActor
internal enum ImageUploader {
    static func upload(_ image: UIImage, messageId: String, index: Int, session: DeviceSession,
                       progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> String {
        let jpeg = try prepare(image)
        let checksum = Data(SHA256.hash(data: jpeg.data)).base64EncodedString()
        struct Input: Encodable {
            let requestId: String
            let contentType = "image/jpeg"
            let bytes: Int
            let width: Int
            let height: Int
            let checksum: String
        }
        struct Output: Decodable { let attachmentId: String; let uploadUrl: URL; let headers: [String: String] }
        let output: Output = try await session.api.request("uploads", method: "POST", authenticated: true,
            body: ReceptionAPI.encode(Input(requestId: requestId(messageId: messageId, index: index, checksum: checksum),
                                            bytes: jpeg.data.count, width: jpeg.width, height: jpeg.height, checksum: checksum)))
        guard ["https", "http"].contains(output.uploadUrl.scheme ?? "") else {
            throw ReceptionAPIError(code: "invalid_upload_url", status: 0)
        }
        var request = URLRequest(url: output.uploadUrl)
        request.httpMethod = "PUT"
        request.timeoutInterval = 60
        // The storage signature covers these headers, including If-Match, so they go out exactly as returned.
        for (name, value) in output.headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: jpeg.data, delegate: UploadProgress(update: progress))
            if let http = response as? HTTPURLResponse { ReceptionAPI.logRateLimit(http) }
            if let http = response as? HTTPURLResponse, http.statusCode == 412,
               output.headers.keys.contains(where: { $0.caseInsensitiveCompare("If-Match") == .orderedSame }) {
                // A successful PUT whose response was lost fails its conditional retry; the message POST checks the bytes.
                return output.attachmentId
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // Storage replies never start a Reception cooldown; their wait only shapes the ordinary backoff.
                throw ReceptionAPIError(code: "upload_failed", status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                        retryAfter: (response as? HTTPURLResponse).flatMap { ReceptionAPI.retryAfter($0, maximum: 300) })
            }
        } catch let error as ReceptionAPIError { throw error }
        catch let error as URLError {
            throw ReceptionAPIError(code: "upload_failed", status: 0, urlErrorCode: error.code.rawValue)
        } catch { throw ReceptionAPIError(code: "upload_failed", status: 0) }
        return output.attachmentId
    }

    /// Every retry of the same photo reuses its reservation: a UUID derived from the message, position and bytes.
    private static func requestId(messageId: String, index: Int, checksum: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("\(messageId):\(index):\(checksum)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid).uuidString
    }

    private static func prepare(_ image: UIImage) throws -> (data: Data, width: Int, height: Int) {
        guard image.size.width > 0, image.size.height > 0,
              image.size.width.isFinite, image.size.height.isFinite else {
            throw ReceptionAPIError(code: "invalid_image", status: 0)
        }
        var edge: CGFloat = 2048
        for _ in 0..<5 {
            let scale = min(1, edge / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, (image.size.width * scale).rounded()),
                              height: max(1, (image.size.height * scale).rounded()))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in stride(from: 0.85, through: 0.25, by: -0.1) {
                if let data = resized.jpegData(compressionQuality: quality), data.count <= 1_048_576 {
                    return (data, Int(size.width), Int(size.height))
                }
            }
            edge *= 0.75
        }
        throw ReceptionAPIError(code: "image_too_large", status: 0)
    }
}
