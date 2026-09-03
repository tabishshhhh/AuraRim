import Foundation

/// Update abstraction (spec §29). Production builds wire this to Sparkle
/// (`SPUStandardUpdaterController`) with a signed appcast feed; the protocol
/// keeps Sparkle out of feature code so the app builds without the dependency
/// during development.
@MainActor
protocol UpdateManaging: AnyObject {
    var automaticChecks: Bool { get set }
    func checkForUpdates()
}

/// Development stub. See README → "Sparkle setup" for the production wiring:
/// add the Sparkle SwiftPM package, set `SUFeedURL` + `SUPublicEDKey` in
/// Info.plist, and forward these calls to `SPUStandardUpdaterController`.
@MainActor
final class StubUpdateManager: UpdateManaging {
    var automaticChecks = true
    func checkForUpdates() {
        Log.updates.info("Check for updates requested (Sparkle not wired in this build)")
    }
}
