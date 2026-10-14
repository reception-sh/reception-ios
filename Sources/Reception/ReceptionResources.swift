import Foundation

internal enum ReceptionResources {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let classBundle = Bundle(for: BundleToken.self)
        guard let url = classBundle.url(forResource: "Reception", withExtension: "bundle"),
              let resources = Bundle(url: url) else { return classBundle }
        return resources
        #endif
    }()

    private final class BundleToken {}
}
