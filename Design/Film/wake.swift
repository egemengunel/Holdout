import CoreGraphics
import Foundation
// Nudges the pointer by a pixel and back, which counts as user activity and wakes a dimmed Touch Bar.
let p = CGEvent(source: nil)!.location
for d in [1.0, 0.0] { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x + d, y: p.y), mouseButton: .left)!.post(tap: .cghidEventTap); usleep(50000) }
