//
//  IconPulse.swift
//  Holdout
//

import AppKit

/// How the Control Strip icon signals status: the color says what, the motion says how urgent.
/// The motion is a Core Animation the render server plays, so the app isn't woken per frame.
enum IconPulse: Equatable {
    case idle
    /// Green check that flashes quickly a few times after a session finishes, glows down,
    /// then cross-fades back to the hand.
    case done(at: TimeInterval)
    /// Blue, slow breathing.
    case working
    /// Amber, quicker pulse.
    case waiting
    /// Red, hard blink.
    case alert

    static let idleSymbol = "hand.raised.fill"
    /// Roughly the Touch Bar's default button gray, so the pulse dims toward a resting button.
    static let resting = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)

    private static let doneFlashes = 3
    private static let doneFlashPeriod: TimeInterval = 0.5
    private static let doneGlowDown: TimeInterval = 1.5
    static let doneDuration = Double(doneFlashes) * doneFlashPeriod + doneGlowDown

    var symbol: String {
        switch self {
        case .idle: Self.idleSymbol
        case .done: "checkmark"
        case .working: "apple.terminal.on.rectangle.fill"
        case .waiting: "hand.tap.fill"
        case .alert: "exclamationmark.triangle.fill"
        }
    }

    /// The full-strength color, or nil for a plain button.
    var color: NSColor? {
        switch self {
        case .idle: nil
        case .done: .systemGreen
        case .working: .systemBlue
        case .waiting: .systemOrange
        case .alert: .systemRed
        }
    }

    /// The background animation, started `elapsed` seconds in; nil for a still color.
    func animation(elapsed: TimeInterval) -> CAAnimation? {
        switch self {
        case .idle:
            return nil
        case .working:
            return breathe(floor: 0.35, period: 2.4)
        case .waiting:
            return breathe(floor: 0.25, period: 0.9)
        case .alert:
            let blink = CAKeyframeAnimation(keyPath: "backgroundColor")
            blink.values = [shade(1), shade(0.1)]
            blink.keyTimes = [0, 0.5, 1]
            blink.calculationMode = .discrete
            blink.duration = 0.5
            blink.repeatCount = .infinity
            return blink
        case .done:
            // Three quick flashes that each start bright, then an eased glow down to resting.
            var values: [CGColor] = []
            var times: [Double] = []
            for flash in 0..<Self.doneFlashes {
                let start = Double(flash) * Self.doneFlashPeriod
                values += [shade(1), shade(0.1)]
                times += [start, start + Self.doneFlashPeriod / 2]
            }
            values += [shade(1), shade(0)]
            times += [Double(Self.doneFlashes) * Self.doneFlashPeriod, Self.doneDuration]

            let flashes = CAKeyframeAnimation(keyPath: "backgroundColor")
            flashes.values = values
            flashes.keyTimes = times.map { NSNumber(value: $0 / Self.doneDuration) }
            flashes.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
            flashes.duration = Self.doneDuration
            flashes.timeOffset = elapsed
            flashes.fillMode = .forwards
            flashes.isRemovedOnCompletion = false
            return flashes
        }
    }

    private func breathe(floor: Double, period: TimeInterval) -> CAAnimation {
        let breathe = CABasicAnimation(keyPath: "backgroundColor")
        breathe.fromValue = shade(floor)
        breathe.toValue = shade(1)
        breathe.duration = period / 2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return breathe
    }

    /// This state's color at `intensity`, blended down toward the resting gray.
    func shade(_ intensity: Double) -> CGColor {
        guard let color = color?.usingColorSpace(.sRGB) else { return Self.resting.cgColor }
        return (Self.resting.blended(withFraction: intensity, of: color) ?? color).cgColor
    }
}
