import AppKit
import MetalKit
import SwiftUI

/// The Metal view the river draws into; turns mouse and trackpad input into River calls.
final class RiverMTKView: MTKView {
    weak var river: River?
    private var downAt = 0.0, moved: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with e: NSEvent) { river?.mouseMoved(to: point(e)) }
    override func mouseExited(with e: NSEvent) { river?.mouseMoved(to: nil) }

    override func mouseDown(with e: NSEvent) {
        downAt = e.timestamp
        moved = 0
        river?.beginDrag()
    }

    override func mouseDragged(with e: NSEvent) {
        moved += abs(e.deltaX)
        river?.drag(by: e.deltaX)
        river?.mouseMoved(to: point(e))
    }

    override func mouseUp(with e: NSEvent) {
        river?.endDrag()
        river?.mouseMoved(to: point(e))
        if moved < 5 && e.timestamp - downAt < 0.5 { river?.click(at: point(e)) }
    }

    /// Mouse wheel and vertical two-finger scroll zoom; horizontal two-finger scroll scrubs the river.
    override func scrollWheel(with e: NSEvent) {
        guard let river else { return }
        if e.hasPreciseScrollingDeltas {
            if abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) {
                river.drag(by: e.scrollingDeltaX)
            } else {
                river.zoom(by: exp(Double(-e.scrollingDeltaY) * 0.01))
            }
        } else if e.scrollingDeltaY != 0 {
            river.zoom(by: 1 - Double(e.scrollingDeltaY.sign == .minus ? -1 : 1) * 0.09)
        }
    }

    override func magnify(with e: NSEvent) { river?.zoom(by: 1 / (1 + Double(e.magnification))) }
}

struct RiverViewRepresentable: NSViewRepresentable {
    let river: River

    func makeNSView(context: Context) -> RiverMTKView {
        let v = RiverMTKView(frame: .zero, device: river.renderer.device)
        v.river = river
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.preferredFramesPerSecond = 120
        v.delegate = river
        return v
    }

    func updateNSView(_ nsView: RiverMTKView, context: Context) {}
}
