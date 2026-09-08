import SwiftUI

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

extension View {
    /// Applies a Liquid Glass background (macOS 26+) with a graceful material
    /// fallback on earlier systems. Used for the panel's cards.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 12, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive),
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08)))
        }
    }
}
