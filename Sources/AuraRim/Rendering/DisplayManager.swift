import AppKit
import CoreGraphics

/// Notch/safe-area geometry for a display, in that display's own points with
/// origin at the top-left of the screen (spec §67).
struct NotchGeometry: Sendable, Equatable {
    var hasNotch: Bool
    var centerX: CGFloat   // notch center, points from left
    var width: CGFloat
    var height: CGFloat

    static let none = NotchGeometry(hasNotch: false, centerX: 0, width: 0, height: 0)
}

/// A stable, Sendable description of one display (spec §71: identify by UUID,
/// never by array index).
struct DisplayInfo: Identifiable, Sendable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect          // global AppKit points (origin bottom-left)
    let scale: CGFloat
    let isBuiltIn: Bool
    let refreshRate: Double
    let notch: NotchGeometry
}

/// Enumerates displays and republishes on hotplug / reconfiguration (spec §20, §40).
@MainActor
final class DisplayManager {
    private(set) var displays: [DisplayInfo] = []
    var onChange: (([DisplayInfo]) -> Void)?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() {
        Log.rendering.info("Screen parameters changed; re-enumerating displays")
        refresh()
        onChange?(displays)
    }

    func refresh() {
        displays = NSScreen.screens.compactMap { Self.info(for: $0) }
    }

    private static func info(for screen: NSScreen) -> DisplayInfo? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        let uuid = displayUUID(id) ?? "screen-\(id)"
        let isBuiltIn = CGDisplayIsBuiltin(id) != 0
        let name = screen.localizedName
        let scale = screen.backingScaleFactor
        let refresh = screen.maximumFramesPerSecond > 0 ? Double(screen.maximumFramesPerSecond) : 60

        return DisplayInfo(
            id: id, uuid: uuid, name: name, frame: screen.frame, scale: scale,
            isBuiltIn: isBuiltIn, refreshRate: refresh,
            notch: notchGeometry(for: screen))
    }

    private static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = CFUUIDCreateString(nil, cf.takeRetainedValue())
        return uuid as String?
    }

    /// Derive notch width from the menu-bar areas either side of it (macOS 12+).
    private static func notchGeometry(for screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return .none }
        let w = screen.frame.width
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notchW = max(0, w - left - right)
        // If we couldn't read the auxiliary areas, fall back to a typical width.
        let width = notchW > 10 ? notchW : 200
        return NotchGeometry(hasNotch: true, centerX: w / 2, width: width, height: top)
    }
}
