import SwiftUI
import Observation

/// Central, user-facing application state (spec §62). High-frequency audio state
/// is intentionally *not* here — it flows through `AnimationStateBus`.
///
/// Every stored preference persists to `Preferences` on write, so the UI can
/// bind directly with no explicit "save" step (spec §21: no Apply button).
@MainActor
@Observable
final class AppState {
    private let prefs: Preferences

    var rimEnabled: Bool { didSet { prefs.set(rimEnabled, .rimEnabled) } }
    var animationMode: AnimationMode { didSet { prefs.set(animationMode.rawValue, .animationMode) } }

    var thickness: Double { didSet { prefs.set(thickness, .thickness) } }      // 2…40
    var glow: Double { didSet { prefs.set(glow, .glow) } }                      // 0…100
    var brightness: Double { didSet { prefs.set(brightness, .brightness) } }    // 0…100
    var colorBalance: Double { didSet { prefs.set(colorBalance, .colorBalance) } } // 0…100

    var albumColorEnabled: Bool { didSet { prefs.set(albumColorEnabled, .albumColorEnabled) } }
    var primaryColor: ColorValue { didSet { prefs.set(primaryColor, .primaryColor) } }
    var secondaryColor: ColorValue { didSet { prefs.set(secondaryColor, .secondaryColor) } }

    var notchEnabled: Bool { didSet { prefs.set(notchEnabled, .notchEnabled) } }
    var showOverFullscreen: Bool { didSet { prefs.set(showOverFullscreen, .showOverFullscreen) } }

    var showInDock: Bool { didSet { prefs.set(showInDock, .showInDock) } }
    var launchAtLogin: Bool { didSet { prefs.set(launchAtLogin, .launchAtLogin) } }
    var playerWindowEnabled: Bool { didSet { prefs.set(playerWindowEnabled, .playerWindowEnabled) } }

    var onboardingComplete: Bool { didSet { prefs.set(onboardingComplete, .onboardingComplete) } }

    /// Stable UUID strings of displays with the rim enabled (spec §71).
    var selectedDisplayUUIDs: Set<String> { didSet { prefs.setDisplayUUIDs(selectedDisplayUUIDs) } }

    // MARK: Non-persisted live state
    var currentTrack: TrackMetadata?
    /// Colors extracted from current album art. Not persisted; recomputed live.
    var albumColors: (primary: ColorValue, secondary: ColorValue)?
    /// Snapshot of discovered displays, for the picker.
    var displays: [DisplayInfo] = []
    var audioPermission: PermissionState = .unknown
    var licenseState: LicenseState = .unactivated

    init(prefs: Preferences = Preferences()) {
        self.prefs = prefs
        rimEnabled = prefs.bool(.rimEnabled)
        animationMode = AnimationMode(rawValue: prefs.int(.animationMode)) ?? .musicSync
        thickness = prefs.double(.thickness)
        glow = prefs.double(.glow)
        brightness = prefs.double(.brightness)
        colorBalance = prefs.double(.colorBalance)
        albumColorEnabled = prefs.bool(.albumColorEnabled)
        primaryColor = prefs.color(.primaryColor, default: .vibrantViolet)
        secondaryColor = prefs.color(.secondaryColor, default: .coolBlue)
        notchEnabled = prefs.bool(.notchEnabled)
        showOverFullscreen = prefs.bool(.showOverFullscreen)
        showInDock = prefs.bool(.showInDock)
        launchAtLogin = prefs.bool(.launchAtLogin)
        playerWindowEnabled = prefs.bool(.playerWindowEnabled)
        onboardingComplete = prefs.bool(.onboardingComplete)
        selectedDisplayUUIDs = prefs.displayUUIDs()
    }

    /// The colors the rim should currently target, resolving album vs. manual
    /// (spec §11). Album colors win only when enabled and available.
    var targetColors: (primary: ColorValue, secondary: ColorValue) {
        if albumColorEnabled, let a = albumColors {
            return a
        }
        return (primaryColor, secondaryColor)
    }
}
