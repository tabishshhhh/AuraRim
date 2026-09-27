import SwiftUI

/// A circular icon button that smoothly expands into a labeled pill on hover
/// (matches the reference "Back 15" interaction). Used across the player.
struct HoverExpandButton: View {
    let icon: String
    let label: String
    var prominent: Bool = false
    var active: Bool = false
    let action: () -> Void

    @State private var hover = false

    private var height: CGFloat { prominent ? 60 : 48 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: prominent ? 22 : 17, weight: .semibold))
                if hover {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(active ? Color.accentColor : .white)
            .frame(height: height)
            .padding(.horizontal, hover ? 18 : 0)
            .frame(minWidth: height)
            .background(.white.opacity(prominent ? 0.16 : 0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.18 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { hover = h }
        }
    }
}
