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
        /// Defaults to nil, using closeIcon. An image such as `Image("Close")`, drawn in its own colors.
        public var closeImage: Image?
        /// Defaults to nil, using the default system font design.
        public var fontDesign: Font.Design?
        /// Defaults to nil (system font); a registered font name overrides local fontDesign.
        /// An explicit dashboard font design uses that system font instead.
        /// Reuse the exact font/PostScript name working in the host's Font.custom or UIFont(name:size:).
        /// Display labels, filenames and family names can differ; UIFont.fontNames(forFamilyName:) lists valid names.
        public var fontFamily: String?
        /// Defaults to true, fading older outgoing messages.
        public var fadesOlderMessages = true
        /// Defaults to nil, using the built-in chat bubbles symbol.
        public var welcomeIcon: WelcomeIcon?
        /// Defaults to nil, using the tertiary label color. Applies to symbols, not images.
        public var welcomeIconColor: Color?
        /// Points before Dynamic Type scaling. Defaults to nil, using the built-in 44 points.
        public var welcomeIconSize: CGFloat?
        /// Defaults to .zero. Moves the icon from its centered position without moving the welcome text.
        public var welcomeIconOffset = CGSize.zero
        /// Defaults to false.
        public var hidesTitle = false
        /// Defaults to false.
        public var hidesWelcomeTitle = false
        /// Defaults to false.
        public var hidesWelcomeText = false

        // Remote-only settings from the dashboard's published appearance.
        internal var showsTeamPhotos = false
        internal var showsTeamNames = false
        internal var remoteCloseImage: URL?
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
