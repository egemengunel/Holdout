//
//  FlexibleWidthView.swift
//  Holdout
//

import AppKit

/// Touch Bar content that fills whatever space the other items leave.
/// The Touch Bar sizes items purely from `intrinsicContentSize` and hides (rather than
/// clips) one that doesn't fit, so this starts small and grows once it can measure.
final class FlexibleWidthView: NSView {
    private let minWidth: CGFloat
    private let height: CGFloat
    private var width: CGFloat

    init(minWidth: CGFloat, height: CGFloat) {
        self.minWidth = minWidth
        self.height = height
        self.width = minWidth
        super.init(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: height) }

    override func layout() {
        super.layout()
        fillAvailableWidth()
    }

    private func fillAvailableWidth() {
        guard let window else { return }
        let leading = convert(bounds.origin, to: nil).x
        let available = (window.frame.width - leading - Self.trailingMargin).rounded(.down)
        guard available >= minWidth, abs(available - width) > 1 else { return }
        width = available
        invalidateIntrinsicContentSize()
    }

    private static let trailingMargin: CGFloat = 8

    var debugDescriptionForLayout: String {
        "window=\(window?.frame.width ?? -1) leading=\(window == nil ? -1 : convert(bounds.origin, to: nil).x) width=\(width)"
    }
}
