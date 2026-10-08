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
    /// Also plays for a successful Xcode build, with a hammer instead of the check.
    /// A failed build plays it in red with the hammer, then clears like the rest.
    case done(at: TimeInterval, symbol: String = "checkmark", isFailure: Bool = false)
    /// Blue, slow breathing.
    case working
    /// Amber, quicker pulse.
    case waiting
    /// Red, quick eased flashes, like the done check's but continuing until seen.
    /// Red until you open the Mac tab: the only persistent red, for Mac distress.
    case alert
    /// Orange, two soft flashes that settle back to the hand: worth a glance, not urgent.
    case headsUp(at: TimeInterval, symbol: String)

    static let idleSymbol = "hand.raised.fill"
    /// Roughly the Touch Bar's default button gray, so the pulse dims toward a resting button.
    static let resting = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)

    private static let doneFlashes = 3
    private static let doneFlashPeriod: TimeInterval = 0.5
    private static let doneGlowDown: TimeInterval = 1.5
    static let doneDuration = Double(doneFlashes) * doneFlashPeriod + doneGlowDown
    static let headsUpDuration: TimeInterval = 2.6

    /// For states that play once and settle: when they began and how long they last.
    var transient: (startedAt: TimeInterval, duration: TimeInterval)? {
        switch self {
        case let .done(at, _, _): (at, Self.doneDuration)
        case let .headsUp(at, _): (at, Self.headsUpDuration)
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .idle: Self.idleSymbol
        case let .done(_, symbol, _): symbol
        case .working: "apple.terminal.on.rectangle.fill"
        case .waiting: "hand.tap.fill"
        case .alert: "exclamationmark.triangle.fill"
        case let .headsUp(_, symbol): symbol
        }
    }

    /// The full-strength color, or nil for a plain button.
    var color: NSColor? {
        switch self {
        case .idle: nil
        case let .done(_, _, isFailure): isFailure ? .systemRed : .systemGreen
        case .working: .systemBlue
        case .waiting: .systemOrange
        case .alert: .systemRed
        case .headsUp: .systemOrange
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
            // The done check's quick eased flash, in red, until you look.
            let flash = CAKeyframeAnimation(keyPath: "backgroundColor")
            flash.values = [shade(1), shade(0.1), shade(1)]
            flash.keyTimes = [0, 0.5, 1]
            flash.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 2)
            flash.duration = Self.doneFlashPeriod
            flash.repeatCount = .infinity
            return flash
        case .headsUp:
            // Gentler than the done check: two slow flashes that never reach full strength.
            let flashes = CAKeyframeAnimation(keyPath: "backgroundColor")
            flashes.values = [shade(0), shade(0.7), shade(0.15), shade(0.7), shade(0)]
            flashes.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            flashes.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
            flashes.duration = Self.headsUpDuration
            flashes.timeOffset = elapsed
            flashes.fillMode = .forwards
            flashes.isRemovedOnCompletion = false
            return flashes
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
