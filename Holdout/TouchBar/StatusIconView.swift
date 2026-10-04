//
//  StatusIconView.swift
//  Holdout
//

import AppKit

/// The Control Strip icon, drawn entirely in Core Animation layers:
/// - The colored background is this view's layer, animated by Core Animation. A bordered
///   NSButton re-renders its bezel in software every time its color changes (~35% CPU while
///   pulsing).
/// - The symbol is a pre-rendered white bitmap. Template symbols in a custom Touch Bar view
///   (NSImageView or a borderless NSButton) draw dimmed gray whatever their tint.
/// - An invisible borderless button on top takes the taps.
final class StatusIconView: NSView {
    var onPress: (() -> Void)?

    private static let size = NSSize(width: 55, height: 30)
    private static let crossfade: TimeInterval = 0.5
    /// Matches the glyphs of the system's Control Strip buttons.
    private static let glyphPointSize: CGFloat = 15
    private static let countFont = NSFont.systemFont(ofSize: 15)
    private static let gap: CGFloat = 5

    private let glyphLayer = CALayer()
    private let countLayer = CATextLayer()
    private let tapTarget = NSButton()
    private var pulse: IconPulse?
    private var symbol = ""
    private var glyphSize = CGSize.zero
    private var settle: DispatchWorkItem?

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = IconPulse.resting.cgColor

        glyphLayer.contentsGravity = .resizeAspect
        countLayer.font = Self.countFont
        countLayer.fontSize = Self.countFont.pointSize
        countLayer.foregroundColor = NSColor.white.cgColor
        countLayer.alignmentMode = .left
        layer?.addSublayer(glyphLayer)
        layer?.addSublayer(countLayer)

        tapTarget.isBordered = false
        tapTarget.title = ""
        tapTarget.target = self
        tapTarget.action = #selector(pressed)
        tapTarget.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tapTarget)
        NSLayoutConstraint.activate([
            tapTarget.leadingAnchor.constraint(equalTo: leadingAnchor),
            tapTarget.trailingAnchor.constraint(equalTo: trailingAnchor),
            tapTarget.topAnchor.constraint(equalTo: topAnchor),
            tapTarget.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setSymbol(IconPulse.idleSymbol, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    @objc private func pressed() {
        onPress?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        glyphLayer.contentsScale = scale
        countLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let countText = countLayer.string as? String ?? ""
        let countWidth = countText.isEmpty ? 0 : (countText as NSString).size(withAttributes: [.font: Self.countFont]).width
        let contentWidth = glyphSize.width + (countText.isEmpty ? 0 : Self.gap + countWidth)
        let left = (bounds.width - contentWidth) / 2
        glyphLayer.frame = CGRect(x: left, y: (bounds.height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height)
        let lineHeight = ceil(Self.countFont.ascender - Self.countFont.descender)
        countLayer.frame = CGRect(x: glyphLayer.frame.maxX + Self.gap, y: (bounds.height - lineHeight) / 2, width: countWidth + 2, height: lineHeight)
        CATransaction.commit()
    }

    /// The working-session count beside the symbol; nil hides it.
    func setCount(_ count: Int?) {
        let text = count.map(String.init) ?? ""
        guard text != countLayer.string as? String else { return }
        countLayer.string = text
        needsLayout = true
    }

    func show(_ next: IconPulse, reduceMotion: Bool) {
        guard next != pulse else { return }
        pulse = next
        settle?.cancel()
        guard let layer else { return }

        var elapsed: TimeInterval = 0
        if let (startedAt, duration) = next.transient {
            elapsed = Date.now.timeIntervalSince1970 - startedAt
            // Already over (e.g. Holdout started after it finished): just rest.
            guard elapsed < duration else {
                show(.idle, reduceMotion: reduceMotion)
                return
            }
            // Cross-fade back to the hand as the glow finishes.
            let settle = DispatchWorkItem { [weak self] in
                self?.setSymbol(IconPulse.idleSymbol, animated: true)
                self?.layer?.removeAllAnimations()
            }
            self.settle = settle
            DispatchQueue.main.asyncAfter(deadline: .now() + duration - elapsed - Self.crossfade / 2, execute: settle)
        }

        setSymbol(next.symbol, animated: true)
        layer.removeAllAnimations()
        // The model value is what shows once an animation ends (done) or when motion is reduced.
        if next.transient != nil {
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
        guard let glyph = Self.whiteGlyph(name, weight: name == "checkmark" ? .semibold : .regular) else { return }
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.crossfade
            glyphLayer.add(fade, forKey: "symbol")
        }
        glyphLayer.contents = glyph.image
        glyphSize = glyph.size
        needsLayout = true
    }

    /// The symbol rendered once into a plain (non-template) white bitmap, so nothing tints it.
    private static func whiteGlyph(_ name: String, weight: NSFont.Weight) -> (image: CGImage, size: CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }

        let scale: CGFloat = 2
        let size = symbol.size
        guard let context = CGContext(
            data: nil,
            width: Int(ceil(size.width * scale)),
            height: Int(ceil(size.height * scale)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { ($0, size) }
    }
}
