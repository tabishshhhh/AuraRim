import Foundation

/// Typed wrapper over UserDefaults so string keys are never scattered across
/// the project (spec §72). Values are plain and cheap; complex values are
/// stored as JSON.
struct Preferences {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    enum Key: String {
        case rimEnabled, animationMode, gradientMode, thickness, glow, brightness
        case colorSource, primaryColor, secondaryColor, colorBalance
        case overrideAlbumColor, notchEnabled, showOverFullscreen
        case launchAtLogin, showInDock, startRimOnLaunch, lockScreenPlayer
        case selectedDisplayIDs, playerWindowEnabled, playerWindowFrame
        case onboardingComplete, automaticUpdates
        case lyricsStyle, lyricsLeftWidth
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.rimEnabled.rawValue: true,
            Key.animationMode.rawValue: AnimationMode.musicSync.rawValue,
            Key.gradientMode.rawValue: GradientMode.two.rawValue,
            Key.thickness.rawValue: 14.0,          // logical px, range 2–40
            Key.glow.rawValue: 55.0,               // 0–100 normalized
            Key.brightness.rawValue: 85.0,         // 0–100
            Key.colorSource.rawValue: ColorSource.album.rawValue,
            Key.colorBalance.rawValue: 50.0,       // 0–100, 50 = even
            Key.overrideAlbumColor.rawValue: false, // false = follow album art
            Key.lockScreenPlayer.rawValue: false,
            Key.notchEnabled.rawValue: true,
            Key.showOverFullscreen.rawValue: false,
            Key.launchAtLogin.rawValue: false,
            Key.showInDock.rawValue: false,
            Key.startRimOnLaunch.rawValue: true,
            Key.playerWindowEnabled.rawValue: false,
            Key.onboardingComplete.rawValue: false,
            Key.automaticUpdates.rawValue: true,
            Key.lyricsStyle.rawValue: LyricsStyle.focus.rawValue,
            Key.lyricsLeftWidth.rawValue: 210.0   // player column width in lyrics view
        ])
    }

    // MARK: Scalars
    func bool(_ k: Key) -> Bool { defaults.bool(forKey: k.rawValue) }
    func double(_ k: Key) -> Double { defaults.double(forKey: k.rawValue) }
    func int(_ k: Key) -> Int { defaults.integer(forKey: k.rawValue) }
    func set(_ v: Bool, _ k: Key) { defaults.set(v, forKey: k.rawValue) }
    func set(_ v: Double, _ k: Key) { defaults.set(v, forKey: k.rawValue) }
    func set(_ v: Int, _ k: Key) { defaults.set(v, forKey: k.rawValue) }

    // MARK: Codable values
    func color(_ k: Key, default fallback: ColorValue) -> ColorValue {
        guard let data = defaults.data(forKey: k.rawValue),
              let v = try? JSONDecoder().decode(ColorValue.self, from: data) else { return fallback }
        return v
    }
    func set(_ v: ColorValue, _ k: Key) {
        if let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: k.rawValue) }
    }

    /// Persist display selection by stable UUID string, never array index (spec §71).
    func displayUUIDs() -> Set<String> {
        Set((defaults.array(forKey: Key.selectedDisplayIDs.rawValue) as? [String]) ?? [])
    }
    func setDisplayUUIDs(_ v: Set<String>) {
        defaults.set(Array(v), forKey: Key.selectedDisplayIDs.rawValue)
    }
}
