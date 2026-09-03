import SwiftUI

/// A pure-SwiftUI simulated rim, used only inside onboarding/settings previews
/// (spec §74). It never implies real audio is being captured.
struct RimPreview: View {
    var primary: Color
    var secondary: Color
    var animated: Bool = true

    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.5 + 0.5 * sin(t * 0.9)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [secondary, primary, secondary, primary, secondary],
                        center: .center,
                        angle: .degrees(t * 12)),
                    lineWidth: 6 + breathe * 3)
                .blur(radius: 6 + breathe * 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: [secondary, primary, secondary, primary, secondary],
                                center: .center,
                                angle: .degrees(t * 12)),
                            lineWidth: 3))
                .padding(10)
                .background(Color.black.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}
