//
//  SystemTouchBar.swift
//  Holdout
//

import AppKit

/// Wrappers around the private DFRFoundation / NSTouchBar APIs that every
/// system-wide Touch Bar tool (MTMR, Pock, BetterTouchTool) relies on.
/// Looked up at runtime so a macOS update that removes them fails soft
/// instead of crashing. Not App Store safe.
enum SystemTouchBar {
    /// Full width, covering the Control Strip. `0` keeps the Control Strip visible.
    static let fullWidthPlacement: Int64 = 1

    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    private static func dfrFunction<T>(_ name: String, as type: T.Type) -> T? {
        guard let dfr, let symbol = dlsym(dfr, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func classMethod<T>(_ cls: AnyClass, _ selector: Selector, as type: T.Type) -> T? {
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: type)
    }

    /// Puts `item` in the Control Strip so it stays visible in every app.
    @discardableResult
    static func addToControlStrip(_ item: NSTouchBarItem) -> Bool {
        typealias Add = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void

        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard let add = classMethod(NSTouchBarItem.self, selector, as: Add.self) else { return false }

        add(NSTouchBarItem.self, selector, item)
        return showInControlStrip(item.identifier)
    }

    /// (Re)claims the Control Strip slot. Closing the modal strip, or another app
    /// like Xcode's debugger adding its own item, drops us out of it.
    @discardableResult
    static func showInControlStrip(_ itemIdentifier: NSTouchBarItem.Identifier) -> Bool {
        typealias SetPresence = @convention(c) (NSString, Bool) -> Void

        guard let setPresence = dfrFunction("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self) else { return false }
        setPresence(itemIdentifier.rawValue as NSString, true)
        return true
    }

    /// Shows `touchBar` over whatever app is frontmost. The ✕ (or `minimize`)
    /// hands the Touch Bar back to that app's own controls.
    @discardableResult
    static func present(_ touchBar: NSTouchBar, from itemIdentifier: NSTouchBarItem.Identifier, placement: Int64 = fullWidthPlacement) -> Bool {
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void

        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let present = classMethod(NSTouchBar.self, selector, as: Present.self) else { return false }
        present(NSTouchBar.self, selector, touchBar, placement, itemIdentifier.rawValue as NSString)
        return true
    }

    static func minimize(_ touchBar: NSTouchBar) {
        typealias Minimize = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void

        let selector = NSSelectorFromString("minimizeSystemModalTouchBar:")
        classMethod(NSTouchBar.self, selector, as: Minimize.self)?(NSTouchBar.self, selector, touchBar)
    }
}
