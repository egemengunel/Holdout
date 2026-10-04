//
//  SimulatorStripView.swift
//  Holdout
//

import AppKit

/// The Sim tab: quick controls for the booted iOS Simulator.
final class SimulatorStripView: NSView {
    private static let locations: [(name: String, coordinate: String)] = [
        ("Apple Park", "37.3349,-122.0090"),
        ("London", "51.5072,-0.1276"),
        ("Tokyo", "35.6764,139.6500"),
    ]

    private let infoLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private lazy var sizeSlider = NSSlider(
        value: Double(Simulator.defaultContentSize),
        minValue: 0,
        maxValue: Double(Simulator.contentSizes.count - 1),
        target: self,
        action: #selector(sizeChanged)
    )
    private lazy var statusBarButton = NSButton(title: "9:41", target: self, action: #selector(toggleStatusBar))
    private lazy var controls = NSStackView(views: [
        infoLabel,
        button("circle.lefthalf.filled", "Toggle light and dark", #selector(toggleAppearance)),
        sizeStack,
        button("camera", "Save a screenshot to the Desktop", #selector(screenshot)),
        statusBarButton,
        button("bell", "Send a test push to the running app", #selector(push)),
        button("location", "Cycle simulated location", #selector(cycleLocation)),
    ])
    private lazy var sizeStack = NSStackView(views: [sizeSlider, sizeLabel])

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
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sizeSlider.numberOfTickMarks = Simulator.contentSizes.count
        sizeSlider.allowsTickMarkValuesOnly = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        emptyLabel.textColor = .secondaryLabelColor

        for stack in [controls, empty] {
            stack.orientation = .horizontal
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        sizeStack.spacing = 4
        show(device: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Re-reads which simulator is booted and its current settings.
    func reload() {
        Task {
            let booted = await Simulator.booted()
            if let booted {
                let size = await Simulator.contentSize(booted.udid)
                sizeSlider.integerValue = size
                sizeLabel.stringValue = Simulator.contentSizeLabels[size]
            } else {
                bootCandidate = await Simulator.lastUsed()
            }
            show(device: booted)
        }
    }

    private func show(device: Simulator.Device?) {
        self.device = device
        controls.isHidden = device == nil
        empty.isHidden = device != nil
        infoLabel.stringValue = device.map { Self.shortName($0) } ?? ""
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

    /// The slider fires continuously while dragging; apply only the latest size, one at a time.
    @objc private func sizeChanged() {
        let index = sizeSlider.integerValue
        sizeLabel.stringValue = Simulator.contentSizeLabels[index]
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
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") {
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
