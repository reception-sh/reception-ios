import SwiftUI

extension Reception {
    public struct Appearance {
        /// Defaults to the app accent color.
        public var accentColor: Color = .accentColor
        /// Defaults to nil, using white text and symbols on accent-colored surfaces.
        public var onAccentColor: Color?
        /// Defaults to the localized “Support” title.
        @MainActor public var title: String {
            get { titleOverride ?? Theme.string("Support") }
            set { titleOverride = newValue }
        }
        /// Defaults to the localized “Questions, feedback, or a bug?” headline.
        @MainActor public var welcomeTitle: String {
            get { welcomeTitleOverride ?? Theme.string("Questions, feedback, or a bug?") }
            set { welcomeTitleOverride = newValue }
        }
        /// Defaults to the localized “You're chatting directly with our team.” text.
        @MainActor public var welcomeText: String {
            get { welcomeTextOverride ?? Theme.string("You're chatting directly with our team.") }
            set { welcomeTextOverride = newValue }
        }
        /// Defaults to false; sheets show the native drag indicator.
        public var showsCloseButton = false

        /// Defaults to nil, using the system background.
        public var chatBackground: Color?
        /// Defaults to nil, using the secondary system background.
        public var incomingBackground: Color?
        /// Defaults to nil, using the primary label color.
        public var incomingForeground: Color?
        /// Defaults to nil, following the app's color scheme.
        public var preferredColorScheme: ColorScheme?
        /// Defaults to .xmark.
        public var closeIcon: CloseIcon = .xmark
        /// Defaults to nil, using the default system font design.
        public var fontDesign: Font.Design?
        /// Defaults to nil (system font); a registered font name overrides fontDesign.
        /// Reuse the exact font/PostScript name working in the host's Font.custom or UIFont(name:size:).
        /// Display labels, filenames and family names can differ; UIFont.fontNames(forFamilyName:) lists valid names.
        public var fontFamily: String?
        /// Defaults to true, fading older outgoing messages.
        public var fadesOlderMessages = true

        // Remote-only settings from the dashboard's published appearance.
        internal var showsTeamPhotos = false
        internal var showsTeamNames = false
        /// nil keeps the built-in icon.
        internal var welcomeIcon: AppearanceIcon?
        internal var welcomeIconColor: Color?
        /// Points before Dynamic Type scaling; nil keeps the built-in size.
        internal var welcomeIconSize: CGFloat?
        /// Visual offset from the centered position; it does not move the welcome text.
        internal var welcomeIconOffset = CGSize.zero
        internal var hidesTitle = false
        internal var hidesWelcomeTitle = false
        internal var hidesWelcomeText = false
        internal var closeImage: URL?
        internal var reviewCard = CardStyle()
        internal var offerCard = CardStyle()

        internal struct CardStyle {
            var icon: AppearanceIcon?
            var accessory: AppearanceIcon?
            var button: Color?
            var buttonText: Color?
            /// Points before Dynamic Type scaling for both card icons; nil keeps the built-in size.
            var iconSize: CGFloat?
        }

        private var titleOverride: String?
        private var welcomeTitleOverride: String?
        private var welcomeTextOverride: String?

        public init() {}

    }
}

public enum ReceptionEvent: Hashable {
    case chatOpened, messageSent, imageSent, reviewOpened, paywallOpened
    /// `Reception.shared.deleteData()` completed and local support data was reset.
    case dataDeleted
    /// The service rejected the token from `identify(token:)` with `identity_token_invalid`, `identity_token_expired`
    /// or `identity_not_configured`. Support continues without it; pass a fresh token from your server.
    case identityRejected(ReceptionError)
}
