import AppKit
import SwiftUI

/// Owns the status-bar item and the SwiftUI popover (spec §4, §31).
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState

    init(appState: AppState, actions: ControlPanelActions) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: AppBrand.symbolName,
                                   accessibilityDescription: AppBrand.name)
            button.image?.isTemplate = true          // monochrome menu-bar icon
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(
            rootView: ControlPanelView(state: appState, actions: actions))
        // Let the popover track the SwiftUI content's height so nothing clips.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updateIcon()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        let name = appState.rimEnabled ? AppBrand.symbolActive : AppBrand.symbolName
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: AppBrand.name)
        button.image?.isTemplate = true
    }
}
