import Foundation

extension ReceptionAPI {
    func appearance(etag: String?) async throws -> (value: AppearanceEnvelope?, etag: String?) {
        _ = try await session?.authorizeRequest()
        var request = try urlRequest("appearance", token: nil)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ReceptionAPIError(code: "invalid_response", status: 0)
            }
            if response.statusCode == 304, etag != nil { return (nil, response.value(forHTTPHeaderField: "ETag")) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < AppearanceCache.maximumBytes else {
                    throw ReceptionAPIError(code: "appearance_too_large", status: 200)
                }
                data.append(byte)
            }
            guard response.statusCode == 200 else {
                ReceptionAPI.logRateLimit(response)
                let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
                throw ReceptionAPIError(code: envelope?.error.code ?? "appearance_unavailable", status: response.statusCode,
                                        retryAfter: Self.retryAfter(response))
            }
            guard let value = try? JSONDecoder().decode(AppearanceEnvelope.self, from: data) else {
                throw ReceptionAPIError(code: "invalid_appearance", status: 200)
            }
            return (value, response.value(forHTTPHeaderField: "ETag"))
        } catch let error as ReceptionAPIError { throw error }
        catch let error as URLError {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0,
                                    urlErrorCode: error.code.rawValue)
        } catch {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0)
        }
    }
}
