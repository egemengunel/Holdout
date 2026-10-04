//
//  IconPulse.swift
//  Holdout
//

import AppKit

/// How the Control Strip icon signals status: the color says what, the motion says how urgent.
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

    /// The symbol for this state; `.done` shows its check only while the green glow lasts.
    func symbol(at now: TimeInterval) -> String {
        switch self {
        case .idle: Self.idleSymbol
        case let .done(finishedAt): now - finishedAt < Self.symbolSwap ? "checkmark" : Self.idleSymbol
        case .working: "apple.terminal.on.rectangle.fill"
        case .waiting: "hand.tap.fill"
        case .alert: "exclamationmark.triangle.fill"
        }
    }

    private static let doneFlashes = 3.0
    private static let doneFlashPeriod: TimeInterval = 0.5
    private static let doneFlashing = doneFlashes * doneFlashPeriod
    private static let doneGlowDown: TimeInterval = 1.5
    private static let doneFade = doneFlashing + doneGlowDown
    /// The check fades out and the hand fades in around this moment, over `symbolCrossfade`.
    private static let symbolCrossfade: TimeInterval = 0.5
    private static let symbolSwap = doneFade - symbolCrossfade / 2

    /// 0…1 opacity for the symbol, dipping to 0 at the moment the done check becomes the hand.
    func symbolOpacity(at now: TimeInterval) -> Double {
        guard case let .done(finishedAt) = self else { return 1 }
        let distance = abs(now - finishedAt - Self.symbolSwap) / (Self.symbolCrossfade / 2)
        return min(1, distance)
    }
    /// Roughly the Touch Bar's default button gray, so the pulse dims toward a resting button.
    private static let resting = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)

    /// The bezel color at `now`, or nil when the icon should look like a plain button.
    func color(at now: TimeInterval, reduceMotion: Bool) -> NSColor? {
        let base: NSColor
        let intensity: Double
        switch self {
        case .idle:
            return nil
        case let .done(finishedAt):
            let elapsed = now - finishedAt
            guard elapsed < Self.doneFade else { return nil }
            base = .systemGreen
            if reduceMotion {
                intensity = 1
            } else if elapsed < Self.doneFlashing {
                // Starts bright: the wave is shifted half a period so each flash peaks first.
                intensity = Self.breathe(elapsed + Self.doneFlashPeriod / 2, period: Self.doneFlashPeriod, floor: 0.1)
            } else {
                // The last flash ends at full brightness; ease it down from there.
                let progress = (elapsed - Self.doneFlashing) / Self.doneGlowDown
                intensity = 1 - progress * progress * (3 - 2 * progress)
            }
        case .working:
            base = .systemBlue
            intensity = reduceMotion ? 1 : Self.breathe(now, period: 2.4, floor: 0.35)
        case .waiting:
            base = .systemOrange
            intensity = reduceMotion ? 1 : Self.breathe(now, period: 0.9, floor: 0.25)
        case .alert:
            base = .systemRed
            intensity = reduceMotion || now.truncatingRemainder(dividingBy: 0.5) < 0.25 ? 1 : 0.1
        }
        let target = base.usingColorSpace(.sRGB) ?? base
        return Self.resting.blended(withFraction: intensity, of: target) ?? target
    }

    /// A smooth 0…1 wave that never drops below `floor`.
    private static func breathe(_ time: TimeInterval, period: Double, floor: Double) -> Double {
        let wave = 0.5 - 0.5 * cos(2 * .pi * time / period)
        return floor + (1 - floor) * wave
    }
}
