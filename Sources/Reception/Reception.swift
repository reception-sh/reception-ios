import SwiftUI
import Observation

@MainActor @Observable
public final class Reception {
    public enum LogLevel: Int, Comparable, Sendable {
        case off = 0, error = 1, info = 2, debug = 3

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Minimum level that is emitted. Default `.info`. Set before `configure`.
    nonisolated public static var logLevel: LogLevel {
        get { Log.level }
        set { Log.level = newValue }
    }
    /// Receives every emitted line instead of the console. `nil` (default) logs through `os.Logger`.
    nonisolated public static var logHandler: (@Sendable (LogLevel, String) -> Void)? {
        get { Log.handler }
        set { Log.handler = newValue }
    }
    /// Version of the SDK, for example "1.1.0". Sent with device registration and updates.
    nonisolated public static var version: String { SDKVersion.current }

    public static let shared = Reception()
    public private(set) var unreadCount: Int = 0
    /// Mirrors the unread count on the app icon and removes read support notifications from Notification Center.
    /// Set to `false` if the host owns the badge. Push payloads omit the badge after server synchronization.
    public var updatesAppBadge = true {
        didSet {
            guard updatesAppBadge != oldValue else { return }
            session?.preferencesChanged()
        }
    }
    public var isChatOpen: Bool { chat?.isVisible == true }
    /// Every paywall the app offers. Without `paywallAvailability`, all of them are available.
    public var paywalls: [ReceptionPaywall] {
        get { registeredPaywalls }
        set {
            let validated = ReceptionPaywall.validated(newValue)
            guard registeredPaywalls != validated else { return }
            registeredPaywalls = validated
            if paywallAvailability != nil {
                // Keep earlier approvals, with current titles, until the new check completes.
                let approved = Set(availablePaywalls.map(\.id))
                publishPaywalls(validated.filter { approved.contains($0.id) })
            }
            refreshPaywalls()
        }
    }
    /// Optional. Decides whether the current user can see a paywall id, for example by asking your paywall vendor.
    /// The SDK checks at configure, foreground, chat opening and logout.
    public var paywallAvailability: (@MainActor (String) async -> Bool)? {
        didSet { refreshPaywalls(invalidate: true) }
    }
    /// The paywalls that agents can send and cards can open: `paywalls` filtered by `paywallAvailability`.
    public private(set) var availablePaywalls: [ReceptionPaywall] = []
    public var onPaywall: ((String) -> Void)?
    private var registeredPaywalls: [ReceptionPaywall] = []
    private var paywallCheck: Task<Void, Never>?
    private var paywallGeneration = 0
    public var onEvent: ((ReceptionEvent) -> Void)?
    public var appearance: Appearance {
        get { style }
        set { style = newValue }
    }
    /// Disable to use only the host app's local appearance settings.
    public var usesRemoteAppearance: Bool {
        get { remoteAppearanceEnabled }
        set {
            guard remoteAppearanceEnabled != newValue else { return }
            remoteAppearanceEnabled = newValue
            applicationLifecycle.remoteAppearanceSettingChanged()
        }
    }
    /// Nil follows the host app's selected localization. Set a BCP 47 tag for custom in-app language selection.
    public var languageOverride: String? {
        get { selectedLanguage }
        set {
            guard selectedLanguage != newValue else { return }
            selectedLanguage = newValue
            if let newValue {
                Log.debug("Language override set to \(ReceptionLocalization.canonical(newValue))")
            } else {
                Log.debug("Language override cleared")
            }
            session?.preferencesChanged()
        }
    }
    private var selectedLanguage: String?
    internal var remoteAppearanceEnabled = true
    internal let appearanceConfiguration = AppearanceConfiguration()
    /// An uploaded appearance image on this service; IDs must be UUIDs, so remote values cannot choose other paths.
    internal func appearanceImageURL(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return try? session?.api.urlRequest("appearance/images/\(id.lowercased())", token: nil).url
    }

    internal static var resolvedAppearance: Appearance {
        guard shared.usesRemoteAppearance else { return shared.appearance }
        return shared.appearanceConfiguration.active?.applying(to: shared.appearance) ?? shared.appearance
    }
    internal var style = Appearance()
    /// App activity from UIApplication notifications. The SDK's sheet is hosted in a UIHostingController, where
    /// SwiftUI's scenePhase stays background, so chat networking and animations follow this value instead.
    internal var applicationActive = false
    internal var session: DeviceSession?
    internal private(set) var readGeneration = 0
    internal var revision = 0
    internal var presentationRevision = 0
    internal let presenter = ChatPresenter()
    private(set) var chat: ChatModel?
    internal var scope: String?
    internal let unreadMonitor = UnreadMonitor()
    private let applicationLifecycle = ApplicationLifecycle()
    private let logoutRevocations = LogoutRevocations()
    private var refreshTask: Task<Void, Never>?
    private var refreshId: UUID?
    /// The token from `identify(token:)`, in memory only.
    internal var identityToken: IdentityToken?
    /// The last value passed to `identify(token:)`; passing it again changes nothing, whatever happened to it.
    internal var lastIdentityToken: String?
    private init() {}

    /// True once a valid dashboard configuration has been accepted for this process.
    @MainActor public static var isConfigured: Bool { shared.session != nil }

    #if DEBUG
    /// Connects to another Reception service, for example a local backend. Only for Reception's own test apps; call it
    /// once instead of `configure(appId:)`. Release builds don't contain it.
    @_spi(ReceptionTesting) public static func configure(appId: String, serviceURL: URL) {
        ReceptionAPI.serviceURL = serviceURL
        configure(appId: appId)
    }
    #endif

    /// Connects your app to Reception with the App ID from your dashboard.
    public static func configure(appId: String) {
        guard ReceptionAPI.accepts(appId: appId) else {
            Log.error(appId.hasPrefix("ids_")
                ? "Configure refused the identity secret, which belongs only on your server; pass the App ID (app_…)"
                : "Configure refused a malformed App ID; copy it from your dashboard")
            return
        }
        guard shared.scope != appId else {
            Log.debug("Configure ignored, same App ID already active")
            return
        }
        shared.unreadMonitor.setActive(false)
        shared.cancelUnreadRefresh()
        shared.session?.deactivate()
        shared.chat?.stopPolling()
        shared.chat = nil
        shared.scope = appId
        shared.forgetIdentityToken()
        let api = ReceptionAPI(appId: appId)
        shared.appearanceConfiguration.configure(api: api, scope: appId)
        var store = DeviceStore(scope: appId + DeviceStore.generation(for: appId))
        if store.hasConversation, store.credentialsMissing {
            // Keychain items stay on their device, so a restored chat without its session is reset like logout.
            store.clear()
            store = DeviceStore(scope: appId + DeviceStore.generation(for: appId, rotate: true))
            Log.info("Local chat reset, its session is not stored on this device")
        }
        shared.session = DeviceSession(api: api, store: store)
        // No badge sync before the first server sync; the server value is the source of truth.
        shared.unreadCount = 0
        shared.revision += 1
        shared.advancePresentationRevision()
        shared.logoutRevocations.resumed(api: api)
        shared.unreadMonitor.setActive(UIApplication.shared.applicationState == .active)
        shared.applicationLifecycle.start()
        shared.refreshPaywalls()
        Log.info("Configured, SDK \(version)")
        #if DEBUG && targetEnvironment(simulator)
        SetupCheck.startIfRequested(configuredAppId: appId)
        ChatPreview.startIfRequested()
        #endif
    }
    public func setPushToken(_ token: Data, environment: PushEnvironment = .automatic) {
        guard let store = session?.store else {
            Log.error("setPushToken called before configure, ignored")
            Log.debug("Push token ignored, not configured")
            return
        }
        guard !token.isEmpty else {
            Log.debug("Push token ignored, empty token")
            return
        }
        guard let pushEnvironment = environment.resolvedValue() else {
            Log.debug("Push token ignored, environment unresolved")
            return
        }
        var identity = store.pending
        identity.pushToken = token.map { String(format: "%02x", $0) }.joined()
        identity.pushEnvironment = pushEnvironment
        store.pending = identity
        Log.debug("Push token staged, \(token.count * 2) hex chars, \(pushEnvironment.lowercased())")
        if session?.isRegistered == true { refreshUnread(updateDevice: true) }
    }
    /// Presents the standard Reception chat sheet over the app's current screen.
    public func openChat() {
        guard session != nil else {
            Log.error("openChat called before configure, ignored")
            return
        }
        Log.debug("Chat presentation requested")
        presenter.present()
    }
    /// Dismisses the chat sheet presented by `openChat()` or a notification tap. Does nothing when the chat is not
    /// presented by the SDK; a `ReceptionChatView` placed by the host is dismissed by the host.
    public func closeChat() {
        guard session != nil else {
            Log.error("closeChat called before configure, ignored")
            return
        }
        guard presenter.dismiss() else {
            Log.debug("Chat close skipped, chat not presented by the SDK")
            return
        }
    }

    /// Pass `openChat: false` for foreground receipt; the default presents the chat sheet for notification taps.
    @discardableResult
    public func handlePushNotification(userInfo: [AnyHashable: Any], openChat: Bool = true) -> Bool {
        guard let payload = userInfo["reception"] as? [String: Any],
              let id = payload["conversationId"] as? String, !id.isEmpty else {
            Log.debug("Push payload ignored, no conversation id")
            return false
        }
        Log.debug("Push payload recognized, conversation \(id)")
        if openChat { self.openChat() }
        refreshUnread()
        return true
    }
    /// Dismisses chat, resets locally immediately, and retries revoking the old session while the app is active.
    public func logout() {
        guard let session else {
            Log.error("logout called before configure, ignored")
            return
        }
        do {
            if let secret = try session.storedCredentials()?.sessionSecret {
                logoutRevocations.enqueue(api: session.api, sessionSecret: secret)
            }
        } catch {
            Log.error("Session revocation skipped, secure storage unavailable")
        }
        forgetIdentityToken()
        Log.info("Logged out, session revocation queued")
        resetLocal()
        refreshPaywalls(invalidate: true)
    }

    /// Requests deletion of the current device's support data, then resets the local session.
    /// Call before logout or account switching. Failures preserve the session for retry.
    /// An absent or ended session, or an unavailable App ID, can complete without erasing earlier server records.
    public func deleteData() async throws {
        guard let session else {
            Log.error("deleteData called before configure, ignored")
            return
        }
        let generation = presentationRevision
        let secret: String?
        do { secret = try session.storedCredentials()?.sessionSecret }
        catch {
            Log.error("Data deletion failed, secure storage unavailable")
            throw ReceptionError(code: "secure_storage_unavailable", status: 0)
        }
        if let secret {
            do {
                try await RequestContext.$probe.withValue(RequestProbe()) {
                    try await session.api.deleteDevice(sessionSecret: secret)
                }
                Log.info("Data deleted")
            } catch let error as ReceptionAPIError where error.status == 401 && error.code == "invalid_app_id" {
                // The server no longer accepts this app's configuration, so only local completion is known.
                Log.info("Local deletion completed, App ID unavailable")
            } catch let error as ReceptionAPIError {
                if error.status > 0 {
                    Log.error("Data deletion failed, HTTP \(error.status) \(error.code)")
                } else {
                    Log.error("Data deletion failed, network error")
                    if let code = error.urlErrorCode {
                        Log.debug("Data deletion failed, network error, URLError \(code)")
                    }
                }
                throw ReceptionError(code: error.code, status: error.status)
            } catch {
                Log.error("Data deletion failed, network error")
                throw ReceptionError(code: "connection_failed", status: 0)
            }
        } else {
            Log.info("Local deletion completed, no stored session")
        }
        // A response from an old session must not erase a newly configured or logged-in session.
        if presentationRevision == generation {
            forgetIdentityToken()
            resetLocal()
            refreshPaywalls(invalidate: true)
        }
        onEvent?(.dataDeleted)
    }

    private func resetLocal(dismissChat: Bool = true) {
        unreadMonitor.setActive(false)
        cancelUnreadRefresh()
        guard let session, let scope else { return }
        session.invalidate()
        for task in chat?.sends.values ?? [:].values { task.cancel() }
        for task in chat?.pendingTimers.values ?? [:].values { task.cancel() }
        chat?.stopPolling()
        chat = nil
        self.session = DeviceSession(api: session.api,
            store: DeviceStore(scope: scope + DeviceStore.generation(for: scope, rotate: true)), halt: session.halt)
        setUnread(0)
        revision += 1
        if dismissChat { advancePresentationRevision() }
    }
    internal func resetChat(revision: Int, deviceDeleted: Bool = false) {
        guard let session else { return }
        if deviceDeleted {
            let identity = session.store.pending
            resetLocal(dismissChat: false)
            self.session?.store.pending = identity
            return
        }
        unreadMonitor.setActive(false)
        cancelUnreadRefresh()
        session.deactivate()
        chat?.stopPolling()
        for task in chat?.sends.values ?? [:].values { task.cancel() }
        for task in chat?.pendingTimers.values ?? [:].values { task.cancel() }
        session.store.resetChat(revision: revision)
        chat = nil
        self.session = DeviceSession(api: session.api, store: session.store.renewed())
        setUnread(0)
        self.revision += 1
    }

    internal func sessionResumed() {
        guard let session else { return }
        chat?.sendingDisabled = false
        logoutRevocations.resumed(api: session.api)
        appearanceConfiguration.resumed()
        applicationLifecycle.remoteAppearanceSettingChanged()
        unreadMonitor.reschedule()
        chat?.startStream()
    }

    #if DEBUG && targetEnvironment(simulator)
    internal func usePreviewChat(_ model: ChatModel) { chat = model }
    #endif

    internal func chatModel() -> ChatModel {
        if let chat { return chat }
        let model = ChatModel(); chat = model; return model
    }
    @discardableResult
    internal func invalidateRead() -> Int {
        readGeneration &+= 1
        return readGeneration
    }
    internal func noteRead(_ count: Int, generation: Int) {
        guard generation == readGeneration else { return }
        invalidateRead()
        setUnread(count)
    }
    internal func setUnread(_ count: Int) {
        unreadCount = max(0, count)
        AppBadge.sync(unreadCount)
    }
    internal func cancelUnreadRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshId = nil
    }

    private func advancePresentationRevision() {
        presentationRevision += 1
        presenter.dismiss()
    }

    /// Checks `paywalls` again with `paywallAvailability`. Only the latest check can change `availablePaywalls`.
    /// Call with `invalidate: true` when your vendor reports a subscription change, so cards update right after a
    /// purchase and no paywall stays available until the check completes. Without it, the current list stays while checking.
    public func refreshPaywalls(invalidate: Bool = false) {
        paywallGeneration &+= 1
        let generation = paywallGeneration
        paywallCheck?.cancel()
        paywallCheck = nil
        guard let availability = paywallAvailability else {
            publishPaywalls(registeredPaywalls)
            return
        }
        if invalidate { publishPaywalls([]) }
        let candidates = registeredPaywalls
        paywallCheck = Task {
            var approved: [ReceptionPaywall] = []
            for paywall in candidates {
                guard generation == paywallGeneration else { return }
                if await availability(paywall.id) { approved.append(paywall) }
            }
            // A check that ignored cancellation finishes here; a newer check or reset has replaced it.
            guard generation == paywallGeneration else { return }
            paywallCheck = nil
            publishPaywalls(approved)
        }
    }

    private func publishPaywalls(_ paywalls: [ReceptionPaywall]) {
        guard availablePaywalls != paywalls else { return }
        availablePaywalls = paywalls
        session?.preferencesChanged()
    }

    internal func refreshUnread(updateDevice: Bool = false, probe: Bool = false) {
        if updateDevice { cancelUnreadRefresh() }
        guard session?.store.hasStartedChat == true, session?.halt == nil || probe, refreshTask == nil else { return }
        let id = UUID()
        refreshId = id
        refreshTask = Task {
            defer { if refreshId == id { refreshTask = nil; refreshId = nil } }
            repeat {
                await chatModel().refreshUnread(updateDevice: updateDevice, probe: probe)
                guard !Task.isCancelled, session?.halt == nil, !probe,
                      session?.retries["unread"]?.delay != nil else { return }
            } while UIApplication.shared.applicationState == .active
        }
    }
}
