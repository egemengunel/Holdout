// wake: counts as user activity so a dimmed or switched-off Touch Bar comes back: nudges the
// pointer by a pixel and back, and taps Shift alone (which types nothing).
import CoreGraphics
import Foundation
let p = CGEvent(source: nil)!.location
for d in [1.0, 0.0] { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x + d, y: p.y), mouseButton: .left)!.post(tap: .cghidEventTap); usleep(50000) }
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: down)!
    e.flags = down ? .maskShift : []
    e.post(tap: .cghidEventTap); usleep(50000)
}
