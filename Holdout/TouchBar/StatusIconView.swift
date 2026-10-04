//
//  StatusIconView.swift
//  Holdout
//

import AppKit

/// The Control Strip icon. A plain layer rather than an NSButton: a button re-renders its
/// bezel (in software) every time its color changes, which cost ~35% CPU while pulsing.
/// Here the color changes are Core Animations the render server plays on its own.
final class StatusIconView: NSView {
    var onPress: (() -> Void)?

    private static let size = NSSize(width: 55, height: 30)
    private static let crossfade: TimeInterval = 0.5

    private let symbolView = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private let content: NSStackView
    private var pulse: IconPulse?
    private var symbol = ""
    private var settle: DispatchWorkItem?

    init() {
        content = NSStackView(views: [symbolView, countLabel])
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = IconPulse.resting.cgColor

        symbolView.contentTintColor = .white
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.isHidden = true
        content.orientation = .horizontal
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Touch Bar touches are "direct" touches; recognizers ignore them unless told otherwise.
        let press = NSClickGestureRecognizer(target: self, action: #selector(pressed))
        press.allowedTouchTypes = .direct
        addGestureRecognizer(press)

        setSymbol(IconPulse.idleSymbol, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    @objc private func pressed() {
        onPress?()
    }

    /// The working-session count beside the symbol; nil hides it.
    func setCount(_ count: Int?) {
        countLabel.stringValue = count.map(String.init) ?? ""
        countLabel.isHidden = count == nil
    }

    func show(_ next: IconPulse, reduceMotion: Bool) {
        guard next != pulse else { return }
        pulse = next
        settle?.cancel()
        guard let layer else { return }

        var elapsed: TimeInterval = 0
        if case let .done(finishedAt) = next {
            elapsed = Date.now.timeIntervalSince1970 - finishedAt
            // Already over (e.g. Holdout started after it finished): just rest.
            guard elapsed < IconPulse.doneDuration else {
                show(.idle, reduceMotion: reduceMotion)
                return
            }
            // Cross-fade back to the hand as the glow finishes.
            let settle = DispatchWorkItem { [weak self] in
                self?.setSymbol(IconPulse.idleSymbol, animated: true)
                self?.layer?.removeAllAnimations()
            }
            self.settle = settle
            DispatchQueue.main.asyncAfter(deadline: .now() + IconPulse.doneDuration - elapsed - Self.crossfade / 2, execute: settle)
        }

        setSymbol(next.symbol, animated: true)
        layer.removeAllAnimations()
        // The model value is what shows once an animation ends (done) or when motion is reduced.
        if case .done = next {
            layer.backgroundColor = reduceMotion ? next.shade(1) : IconPulse.resting.cgColor
        } else {
            layer.backgroundColor = next.shade(1)
        }
        if !reduceMotion, let animation = next.animation(elapsed: elapsed) {
            layer.add(animation, forKey: "pulse")
        }
    }

    private func setSymbol(_ name: String, animated: Bool) {
        guard name != symbol else { return }
        symbol = name
        // The bare checkmark reads thin next to the filled symbols.
        let weight: NSFont.Weight = name == "checkmark" ? .semibold : .regular
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Holdout")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: weight).applying(.preferringMonochrome()))
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.crossfade
            symbolView.layer?.add(fade, forKey: "symbol")
        }
        symbolView.image = image
    }
}
