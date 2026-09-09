import SwiftUI
import AppKit

/// A drag handle backed by AppKit so it does NOT move the window (unlike a plain
/// SwiftUI shape in a `movableByWindowBackground` panel). Reports horizontal
/// drag deltas and shows the resize cursor.
struct ResizeHandle: NSViewRepresentable {
    var onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView(); v.onDrag = onDrag; return v
    }
    func updateNSView(_ nsView: HandleView, context: Context) { nsView.onDrag = onDrag }

    final class HandleView: NSView {
        var onDrag: (CGFloat) -> Void = { _ in }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func mouseDragged(with event: NSEvent) { onDrag(event.deltaX) }
    }
}
