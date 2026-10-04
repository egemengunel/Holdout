//
//  SimulatorStripView.swift
//  Holdout
//

import AppKit

/// The Sim tab: quick controls for the booted iOS Simulator.
final class SimulatorStripView: NSView {
    /// Xcode 27 replaced Simulator.app with DeviceHub.app; older Xcodes still ship Simulator.
    private static let simulatorAppIDs = ["com.apple.dt.Devices", "com.apple.iphonesimulator"]

    private static let locations: [(name: String, coordinate: String)] = [
        ("Apple Park", "37.3349,-122.0090"),
        ("London", "51.5072,-0.1276"),
        ("Tokyo", "35.6764,139.6500"),
    ]

    /// Current Dynamic Type size, as an index into `Simulator.contentSizes`.
    private var contentSize = Simulator.defaultContentSize

    private let infoLabel = NSTextField(labelWithString: "")
    /// [ − | L | + ]: steps Dynamic Type one size at a time; the middle shows the current size.
    private lazy var textSize: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: ["", "", ""], trackingMode: .momentary, target: self, action: #selector(stepTextSize))
        control.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Smaller text"), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Larger text"), forSegment: 2)
        control.setWidth(36, forSegment: 0)
        control.setWidth(44, forSegment: 1)
        control.setWidth(36, forSegment: 2)
        return control
    }()
    private lazy var statusBarButton = NSButton(title: "9:41", target: self, action: #selector(toggleStatusBar))
    private lazy var controls = NSStackView(views: [
        infoLabel,
        button("circle.lefthalf.filled", "Toggle light and dark", #selector(toggleAppearance)),
        textSize,
        button("camera", "Save a screenshot to the Desktop", #selector(screenshot)),
        statusBarButton,
        button("bell", "Send a test push to the running app", #selector(push)),
        button("location", "Cycle simulated location", #selector(cycleLocation)),
    ])
    /// More controls than fit beside the Control Strip, so they scroll sideways like the Agents pills.
    private let controlsScroll = NSScrollView()

    private let emptyLabel = NSTextField(labelWithString: "No simulator running")
    private lazy var bootButton = NSButton(title: "Boot", target: self, action: #selector(boot))
    private lazy var empty = NSStackView(views: [emptyLabel, bootButton])

    private var device: Simulator.Device?
    private var bootCandidate: Simulator.Device?
    private var cleanStatusBars: Set<String> = []
    private var locationIndex = 0
    private var pendingSize: Int?
    private var isApplyingSize = false
    private var messageResetTask: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)

        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
        emptyLabel.textColor = .secondaryLabelColor

        for stack in [controls, empty] {
            stack.orientation = .horizontal
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
        }

        controlsScroll.drawsBackground = false
        controlsScroll.hasHorizontalScroller = false
        controlsScroll.hasVerticalScroller = false
        controlsScroll.documentView = controls
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsScroll)
        addSubview(empty)
        NSLayoutConstraint.activate([
            controlsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsScroll.topAnchor.constraint(equalTo: topAnchor),
            controlsScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: controlsScroll.contentView.leadingAnchor),
            controls.topAnchor.constraint(equalTo: controlsScroll.contentView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: controlsScroll.contentView.bottomAnchor),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        show(device: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Re-reads which simulator is booted and its current settings.
    func reload() {
        Task {
            let booted = await Simulator.booted()
            if let booted {
                contentSize = await Simulator.contentSize(booted.udid)
            } else {
                bootCandidate = await Simulator.lastUsed()
            }
            show(device: booted)
        }
    }

    private func show(device: Simulator.Device?) {
        self.device = device
        controlsScroll.isHidden = device == nil
        empty.isHidden = device != nil
        infoLabel.stringValue = device.map { Self.shortName($0) } ?? ""
        textSize.setLabel(Simulator.contentSizeLabels[contentSize], forSegment: 1)
        bootButton.title = bootCandidate.map { "Boot \($0.name)" } ?? "Boot"
        bootButton.isHidden = bootCandidate == nil
        if let device {
            statusBarButton.bezelColor = cleanStatusBars.contains(device.udid) ? .systemBlue : nil
        }
    }

    // MARK: - Actions

    @objc private func toggleAppearance() {
        guard let udid = device?.udid else { return }
        Task {
            let next = await Simulator.isDark(udid) ? "light" : "dark"
            await Simulator.run(["ui", udid, "appearance", next])
            flash(next == "dark" ? "Dark" : "Light")
        }
    }

    @objc private func stepTextSize() {
        let step = switch textSize.selectedSegment {
        case 0: -1
        case 2: 1
        default: 0
        }
        let index = min(max(contentSize + step, 0), Simulator.contentSizes.count - 1)
        guard index != contentSize else { return }
        applyContentSize(index)
    }

    /// Quick taps can outpace simctl; apply only the latest size, one at a time.
    private func applyContentSize(_ index: Int) {
        contentSize = index
        textSize.setLabel(Simulator.contentSizeLabels[index], forSegment: 1)
        pendingSize = index
        guard !isApplyingSize, let udid = device?.udid else { return }
        isApplyingSize = true
        Task {
            while let size = pendingSize {
                pendingSize = nil
                await Simulator.run(["ui", udid, "content_size", Simulator.contentSizes[size]])
            }
            isApplyingSize = false
        }
    }

    @objc private func screenshot() {
        guard let device else { return }
        let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)", timeZone: .current, calendar: .current))
        let url = URL.desktopDirectory.appending(path: "Simulator Screenshot - \(device.name) - \(stamp).png")
        Task {
            let saved = await Simulator.run(["io", device.udid, "screenshot", url.path])
            flash(saved ? "Saved to Desktop" : "Screenshot failed")
        }
    }

    /// The App Store look: 9:41, full signal, full battery.
    @objc private func toggleStatusBar() {
        guard let udid = device?.udid else { return }
        let isClean = cleanStatusBars.contains(udid)
        Task {
            if isClean {
                await Simulator.run(["status_bar", udid, "clear"])
                cleanStatusBars.remove(udid)
            } else {
                await Simulator.run([
                    "status_bar", udid, "override", "--time", "9:41",
                    "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                    "--cellularMode", "active", "--cellularBars", "4",
                    "--batteryState", "charged", "--batteryLevel", "100",
                ])
                cleanStatusBars.insert(udid)
            }
            show(device: device)
            flash(isClean ? "Status bar restored" : "Clean status bar")
        }
    }

    @objc private func push() {
        guard let udid = device?.udid else { return }
        Task {
            guard let app = await Simulator.runningApp(udid) else {
                flash("Run your app first")
                return
            }
            let payload = URL.temporaryDirectory.appending(path: "holdout-push.json")
            let json = #"{"aps":{"alert":{"title":"Holdout","body":"Test notification"},"sound":"default"}}"#
            try? Data(json.utf8).write(to: payload)
            let sent = await Simulator.run(["push", udid, app, payload.path])
            flash(sent ? "Pushed to \(app.split(separator: ".").last ?? "")" : "Push failed")
        }
    }

    /// Cycles through a few well-known places, then back to no override.
    @objc private func cycleLocation() {
        guard let udid = device?.udid else { return }
        let index = locationIndex
        locationIndex = (locationIndex + 1) % (Self.locations.count + 1)
        Task {
            if index < Self.locations.count {
                let location = Self.locations[index]
                await Simulator.run(["location", udid, "set", location.coordinate])
                flash(location.name)
            } else {
                await Simulator.run(["location", udid, "clear"])
                flash("Location cleared")
            }
        }
    }

    @objc private func boot() {
        guard let candidate = bootCandidate else { return }
        emptyLabel.stringValue = "Booting \(candidate.name)…"
        bootButton.isHidden = true
        Task {
            await Simulator.run(["boot", candidate.udid])
            if let url = Self.simulatorAppIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            emptyLabel.stringValue = "No simulator running"
            reload()
        }
    }

    // MARK: - Helpers

    /// Briefly replaces the device name with what just happened.
    private func flash(_ message: String) {
        infoLabel.stringValue = message
        messageResetTask?.cancel()
        messageResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            infoLabel.stringValue = device.map { Self.shortName($0) } ?? ""
        }
    }

    private func button(_ symbol: String, _ description: String, _ action: Selector) -> NSButton {
        NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description)!, target: self, action: action)
    }

    /// "iPhone 17 Pro Max" → "17 Pro Max"; the tab icon already says iPhone.
    private static func shortName(_ device: Simulator.Device) -> String {
        device.name.replacingOccurrences(of: "iPhone ", with: "")
    }
}
