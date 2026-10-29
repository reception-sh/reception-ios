import UIKit

@MainActor
internal enum DeviceInfo {
    static func payload(identity: DeviceIdentity, identityToken: String? = nil, registration: Bool = false) throws -> Data {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        var values: [String: String] = [
            "platform": "ios",
            "sdkVersion": SDKVersion.current,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            "osVersion": UIDevice.current.systemVersion, "deviceModel": model,
            "locale": Locale.current.identifier, "timezone": TimeZone.current.identifier,
            "language": ReceptionLocalization.appLanguage
        ]
        values["bundleId"] = Bundle.main.bundleIdentifier
        values["externalUserId"] = identity.externalUserId
        values["name"] = identity.name
        values["email"] = identity.email
        if !registration, let pushToken = identity.pushToken, let pushEnvironment = identity.pushEnvironment {
            values["pushToken"] = pushToken
            values["pushEnvironment"] = pushEnvironment
        }
        var body: [String: Any] = values
        body["paywalls"] = Reception.shared.availablePaywalls.map(\.payload)
        body["metadata"] = identity.metadata
        body["updatesAppBadge"] = Reception.shared.updatesAppBadge
        body["urlSchemes"] = Array(LinkPolicy.main.hostSchemes.prefix(20))
        body["handlesLinks"] = Reception.shared.onLink != nil
        if let subscribed = Reception.shared.paidAccess.current { body["subscribed"] = subscribed }
        body["appearance"] = HostAppearanceReport.payload(Reception.shared.appearance,
                                                          usesRemoteAppearance: Reception.shared.usesRemoteAppearance)
        if let identityToken { body["identityToken"] = identityToken }
        do { return try JSONSerialization.data(withJSONObject: body) }
        catch { throw ReceptionAPIError(code: "invalid_device_info", status: 0) }
    }
}
