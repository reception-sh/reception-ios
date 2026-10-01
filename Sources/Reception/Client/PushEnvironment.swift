import Foundation

extension Reception {
    /// `automatic` reads `aps-environment` from the embedded provisioning profile.
    /// Use `sandbox` or `production` to override detection when it is unavailable for the host.
    public enum PushEnvironment: Sendable {
        case automatic, sandbox, production

        internal func resolvedValue() -> String? {
            switch self {
            case .sandbox: return "SANDBOX"
            case .production: return "PRODUCTION"
            case .automatic:
                #if targetEnvironment(simulator)
                return nil
                #else
                guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
                    return "PRODUCTION"
                }
                guard let data = try? Data(contentsOf: url),
                      let start = data.range(of: Data("<?xml".utf8)) ?? data.range(of: Data("<plist".utf8)),
                      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
                      let profile = try? PropertyListSerialization.propertyList(
                        from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
                      let entitlements = profile["Entitlements"] as? [String: Any],
                      let environment = entitlements["aps-environment"] as? String else { return nil }
                switch environment {
                case "development": return "SANDBOX"
                case "production": return "PRODUCTION"
                default: return nil
                }
                #endif
            }
        }
    }
}
