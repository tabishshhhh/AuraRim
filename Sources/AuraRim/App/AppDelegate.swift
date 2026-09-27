import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var controller: RimController?
    private var menuBar: MenuBarController!
    private let license = LicenseManager()
    private let updater: UpdateManaging = StubUpdateManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var player: NowPlayingController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        license.restore()
        appState.licenseState = license.state
        license.onChange = { [weak self] state in self?.appState.licenseState = state }

        applyDockPolicy()

        controller = RimController(appState: appState)
        if controller == nil {
            Log.app.error("Metal unavailable — rim rendering disabled")
        }

        player = NowPlayingController(appState: appState)
        player.onOpenSettings = { [weak self] in self?.showSettings() }
        menuBar = MenuBarController(appState: appState, actions: makeActions())

        if !appState.onboardingComplete {
            showOnboarding()
        }

        // QA helpers to screenshot the UI without manual clicking.
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.menuBar.open() }
        }
        if CommandLine.arguments.contains("--show-player") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.player.show() }
        }
        if CommandLine.arguments.contains("--show-ambient") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.player.showAmbient() }
        }
        Log.app.info("\(AppBrand.name, privacy: .public) launched")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.teardown()
        return .terminateNow
    }

    // MARK: Actions

    private func makeActions() -> ControlPanelActions {
        ControlPanelActions(
            openSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            quit: { NSApp.terminate(nil) },
            requestAudio: { [weak self] in self?.controller?.requestAudioPermissionFlow() },
            showPlayer: { [weak self] in self?.player.show() })
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(appState.showInDock ? .regular : .accessory)
    }

    // MARK: Windows

    private func showSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = SettingsView(state: appState,
                                license: license,
                                requestAudio: { [weak self] in self?.controller?.requestAudioPermissionFlow() })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(AppBrand.name) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        let view = OnboardingView(state: appState,
                                  requestAudio: { [weak self] in self?.controller?.requestAudioPermissionFlow() },
                                  activate: { [weak self] key in
                                      Task { await self?.license.activate(key: key) } },
                                  finish: { [weak self] in
                                      self?.appState.onboardingComplete = true
                                      self?.onboardingWindow?.close()
                                      self?.onboardingWindow = nil
                                  })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 460, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
