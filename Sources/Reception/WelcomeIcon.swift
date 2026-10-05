import SwiftUI

extension Reception {
    /// The icon above the welcome heading.
    public struct WelcomeIcon {
        internal let icon: AppearanceIcon

        /// An SF Symbol, drawn in `welcomeIconColor`.
        public static func symbol(_ name: String) -> WelcomeIcon { WelcomeIcon(icon: .symbol(name)) }
        /// An image such as `Image("Logo")`, drawn in its own colors.
        public static func image(_ image: Image) -> WelcomeIcon { WelcomeIcon(icon: .local(image)) }
        /// No icon.
        public static var hidden: WelcomeIcon { WelcomeIcon(icon: .hidden) }
    }
}
