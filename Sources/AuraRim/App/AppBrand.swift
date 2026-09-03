import SwiftUI

/// Centralized branding. Swap these values (and Assets) to rebrand the app.
/// The spec requires all branding be centralized so a final brand can be
/// substituted later without touching feature code.
enum AppBrand {
    static let name = "AuraRim"
    static let bundleIdentifier = "com.aurarim.app"

    /// SF Symbol used for the menu-bar template icon and header glyph.
    static let symbolName = "circle.dashed"
    static let symbolActive = "circle.circle"

    /// Short privacy copy, reused across onboarding and settings.
    static let privacyAudioCopy =
        "Audio analysis happens entirely on your Mac. Audio is never recorded or uploaded. Microphone access is not required."
    static let privacyMusicCopy =
        "Music access is used only to identify the current track and artwork."
}
