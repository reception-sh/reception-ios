import UIKit

@MainActor
internal final class ApplicationLifecycle: NSObject {
    private var started = false
    private var appearanceTask: Task<Void, Never>?

    func start() {
        if !started {
            started = true
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                name: UIApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                name: UIApplication.didEnterBackgroundNotification, object: nil)
        }
        Reception.shared.applicationActive = UIApplication.shared.applicationState == .active
        updateAppearanceRefresh()
    }

    func remoteAppearanceSettingChanged() {
        guard started else { return }
        updateAppearanceRefresh()
    }

    @objc private func didBecomeActive() {
        Reception.shared.applicationActive = true
        Reception.shared.appearanceConfiguration.becameActive()
        Reception.shared.refreshPaywalls()
        updateAppearanceRefresh()
    }

    @objc private func didEnterBackground() {
        Reception.shared.applicationActive = false
        appearanceTask?.cancel()
        appearanceTask = nil
    }

    private func updateAppearanceRefresh() {
        appearanceTask?.cancel()
        appearanceTask = nil
        guard UIApplication.shared.applicationState == .active,
              Reception.shared.usesRemoteAppearance else { return }
        appearanceTask = Task {
            await Reception.shared.appearanceConfiguration.refreshWhileActive()
        }
    }
}
