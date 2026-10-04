//
//  IconPulse.swift
//  Holdout
//

import AppKit

/// How the Control Strip icon signals status: the color says what, the motion says how urgent.
enum IconPulse: Equatable {
    case idle
    /// Green glow that fades out after a session finishes.
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
        case let .done(finishedAt): now - finishedAt < Self.doneFade ? "checkmark" : Self.idleSymbol
        case .working: "apple.terminal.on.rectangle.fill"
        case .waiting: "hand.tap.fill"
        case .alert: "exclamationmark.triangle.fill"
        }
    }

    private static let doneFade: TimeInterval = 6
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
            let progress = (now - finishedAt) / Self.doneFade
            guard progress < 1 else { return nil }
            base = .systemGreen
            intensity = 1 - progress
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
