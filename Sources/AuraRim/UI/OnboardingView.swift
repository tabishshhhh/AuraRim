import SwiftUI

/// Short first-run onboarding (spec §25). 5 screens, skippable where sensible.
struct OnboardingView: View {
    @Bindable var state: AppState
    var requestAudio: () -> Void
    var activate: (String) -> Void
    var finish: () -> Void

    @State private var step = 0
    @State private var licenseKey = ""

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            footer
        }
        .frame(width: 460, height: 520)
        .background(.regularMaterial)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: systemAudio
        case 2: musicIntegration
        case 3: activation
        default: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            RimPreview(primary: state.primaryColor.color, secondary: state.secondaryColor.color)
                .frame(height: 200)
            Text("Make your screen react to your music.")
                .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("A soft, luminous rim hugs your display and moves with whatever’s playing on your Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var systemAudio: some View {
        infoScreen(
            symbol: "waveform.circle.fill",
            title: "System Audio",
            body: "The app listens to audio playing on your Mac to animate the rim.",
            note: AppBrand.privacyAudioCopy) {
                Button("Allow System Audio") { requestAudio(); step += 1 }
                    .buttonStyle(.borderedProminent)
            }
    }

    private var musicIntegration: some View {
        infoScreen(
            symbol: "music.note.list",
            title: "Music Integration",
            body: "Optional access lets the app read the current song and artwork for automatic colors.",
            note: AppBrand.privacyMusicCopy) {
                HStack {
                    Button("Apple Music") { step += 1 }.buttonStyle(.bordered)
                    Button("Spotify") { step += 1 }.buttonStyle(.bordered)
                    Button("Skip") { step += 1 }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
    }

    private var activation: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(.tint)
            Text("Activation").font(.title2.weight(.semibold))
            Text("Enter your license key to activate this Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            HStack {
                Button("Paste License") {
                    if let s = NSPasteboard.general.string(forType: .string) { licenseKey = s }
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Activate") { activate(licenseKey); step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKey.count < 4)
            }
            licenseStatus
        }
    }

    @ViewBuilder private var licenseStatus: some View {
        switch state.licenseState {
        case .invalid(let reason):
            Text(reason).font(.caption).foregroundStyle(.red)
        case .active:
            Label("Activated", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        default: EmptyView()
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            RimPreview(primary: state.primaryColor.color, secondary: state.secondaryColor.color)
                .frame(height: 180)
            Text("Ready").font(.title.weight(.bold))
            Text("Choose a song and your screen will react automatically.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func infoScreen<Buttons: View>(
        symbol: String, title: String, body: String, note: String,
        @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2.weight(.semibold))
            Text(body).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            buttons()
            Text(note).font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.plain)
            }
            Spacer()
            PageDots(count: 5, index: step)
            Spacer()
            if step < 4 {
                Button(step == 1 || step == 2 || step == 3 ? "Next" : "Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start") { finish() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(.thinMaterial)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle().frame(width: 6, height: 6)
                    .foregroundStyle(i == index ? Color.accentColor : Color.secondary.opacity(0.4))
            }
        }
    }
}
