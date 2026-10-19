import AppKit
import Foundation

final class APIBridge {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var nextID = 0
    private var callbacks: [Int: ([String: Any]) -> Void] = [:]
    var onFailure: ((String) -> Void)?

    init(python: String, script: String, port: String) throws {
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-u", script, "--port", port]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/RoboDKVoiceAccess")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("bridge.log")
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let logHandle = try FileHandle(forWritingTo: log)
        logHandle.seekToEndOfFile()
        process.standardError = logHandle
        try process.run()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var buffer = Data()
            while true {
                let chunk = self.output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let boundary = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: boundary)
                    buffer.removeSubrange(...boundary)
                    guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    DispatchQueue.main.async {
                        if let id = response["id"] as? Int, let callback = self.callbacks.removeValue(forKey: id) { callback(response) }
                    }
                }
            }
            DispatchQueue.main.async {
                self.onFailure?("The connection to RoboDK has closed. Reopen VoiceAccess from RoboDK.")
            }
        }
    }

    func request(_ command: String, itemID: String? = nil, parameters: [String: Any] = [:], completion: @escaping ([String: Any]) -> Void) {
        nextID += 1
        var request: [String: Any] = ["id": nextID, "command": command]
        if let itemID = itemID { request["item_id"] = itemID }
        request.merge(parameters) { _, value in value }
        callbacks[nextID] = completion
        do {
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            callbacks.removeValue(forKey: nextID)
            completion(["ok": false, "error": "Could not send the action to RoboDK."])
        }
    }

    func discardPendingCallbacks() { callbacks.removeAll() }

    func close() {
        onFailure = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

final class VoiceAccessController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private let outline = StationOutlineView()
    private let details = NSTextView()
    private let search = NSSearchField()
    private let status = NSTextField(wrappingLabelWithString: "Connecting to RoboDK…")
    private let execution = NSTextField(wrappingLabelWithString: "No simulation running.")
    private let outputMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private var speechOutput = SpeechOutputMode.automatic
    private var usingOwnVoice = true
    private var voiceOverRunning = false
    private var voiceOverObservation: NSKeyValueObservation?
    private var integration: IntegrationChannel?
    private var queuedCommand: (String, [String])?
    private var hostPID: pid_t?
    private var hostObserver: NSObjectProtocol?
    private var applyingSelection = false
    private let follow = NSButton(checkboxWithTitle: "Follow RoboDK selection", target: nil, action: nil)
    private let narrate = NSButton(checkboxWithTitle: "Narrate simulation", target: nil, action: nil)
    private let rateSlider = NSSlider(value: 175, minValue: 100, maxValue: 350, target: nil, action: nil)
    private let rateValue = NSTextField(labelWithString: "175 words per minute")
    private let voiceInfo = NSTextField(wrappingLabelWithString: "")
    private let speech = LocalSpeech()
    private var bridge: APIBridge?
    private var roots: [StationNode] = []
    private var visibleRoots: [StationNode] = []
    private var visibleChildren: [String: [StationNode]] = [:]
    private var nodes: [String: StationNode] = [:]
    private var selectedID: String?
    private var stationID = ""
    private var lastRDKSelection: [String] = []
    private var lastSpoken = ""
    private var detailSpeech = ""
    private var voiceTest = ""
    private var language = "en"
    private var robodkLanguage = "en"
    private var ui: [String: String] = [:]
    private var localizedButtons: [(NSButton, String)] = []
    private var localizedLabels: [(NSTextField, String)] = []
    private var localizedMenus: [(NSMenuItem, String)] = []
    private var runningPrograms: [String] = []
    private var polling = false
    private var timer: Timer?
    private var selfTestPath: String?
    private var controls: [NSButton] = []
    private var refreshing = false
    private let simulationAdmission = SimulationAdmission()
    private var keyMonitor: Any?
    private var traceHandle: FileHandle?
    private var traceCount = 0
    private var lastAXTrace = Date.distantPast
    private var collapsedNodes = Set<String>()
    private var rebuildingTree = false
    private var toolbarVisible: Bool?
    private var embeddedOptions: [String: String]?
    private var embeddedContent: NSView?
    private var embeddedMenu: NSMenu?
    private var embeddedHostMenu: NSMenu?
    private var embeddedMenuPreserved = false
    private var embeddedChecksRunning = false
    private var readerActive = true
    var embeddedVisibility: ((Bool) -> Void)?

    func createEmbedded(_ options: [String: String]) -> NSView {
        embeddedOptions = options
        hostPID = ProcessInfo.processInfo.processIdentifier
        embeddedHostMenu = NSApp.mainMenu
        makeMenus()
        embeddedMenuPreserved = NSApp.mainMenu === embeddedHostMenu
        makeWindow()
        let content = window.contentView!
        window.contentView = nil
        window.orderOut(nil)
        window.delegate = nil
        window = nil
        let root = EmbeddedStationView(frame: NSRect(x: 0, y: 0, width: 400, height: 850))
        root.appearance = NSAppearance(named: .aqua)
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        let scroll = NSScrollView(frame: root.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = EmbeddedStationDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        root.setAccessibilityLabel("VoiceAccess. Accessible RoboDK station")
        root.keyEquivalent = { [weak self] event in self?.embeddedMenu?.performKeyEquivalent(with: event) ?? false }
        embeddedContent = root
        return root
    }

    func attachEmbedded() {
        window = embeddedContent?.window
        guard window != nil, bridge == nil else { return }
        speech.onStarted = { [weak self] text in self?.lastSpoken = text }
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applySpeechOutput() }
        }
        do {
            bridge = try APIBridge(python: argument("--python") ?? "/usr/bin/python3",
                                  script: argument("--bridge") ?? "", port: argument("--port") ?? "20500")
            bridge?.onFailure = { [weak self] message in self?.status.stringValue = message }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.poll() }
        } catch { showError(error.localizedDescription) }
    }

    func embeddedDidChangeVisibility(_ visible: Bool) {
        window = embeddedContent?.window ?? window
        setReaderActive(visible)
        syncToolbar(visible)
    }

    private func setReaderActive(_ active: Bool) {
        guard readerActive != active else { return }
        readerActive = active
        bridge?.discardPendingCallbacks()
        polling = false; refreshing = false
        simulationAdmission.completed()
        if active { refresh() }
        else {
            queuedCommand = nil
            speech.stop()
            bridge?.request("deactivate") { _ in }
        }
    }

    func embeddedReport(checkNavigation: Bool, preview: String?) -> [String: Any] {
        var report: [String: Any] = [
            "embedded": true, "pid": ProcessInfo.processInfo.processIdentifier,
            "reader_active": readerActive,
            "background_polling_enabled": readerActive,
            "own_speech_active": speech.isSpeaking,
            "speech_queue_pending": speech.pendingText != nil,
            "native_view_in_host_window": embeddedContent?.window != nil,
            "host_window_title": window?.title ?? "", "rows": outline.numberOfRows,
            "tree_has_keyboard_focus": window?.firstResponder === outline,
            "selected_row": outline.selectedRow,
            "selected_name": selectedTreeNode?.name ?? "",
            "voiceover_running": NSWorkspace.shared.isVoiceOverEnabled,
            "host_application_delegate": NSApp.delegate.map { String(describing: type(of: $0)) } ?? "none",
            "host_activation_policy": NSApp.activationPolicy().rawValue,
            "host_menu_preserved": embeddedMenuPreserved,
            "details_available": !details.string.isEmpty,
        ]
        if checkNavigation, let program = nodes.values.first(where: { $0.type == 8 && !$0.children.isEmpty }), window != nil {
            embeddedChecksRunning = true
            defer { embeddedChecksRunning = false }
            report.merge(checkOutlineNavigation(program: program)) { _, value in value }
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, characters: "\u{f701}",
                                        charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125)!
            _ = outline.selectAccessibleRow(0)
            let handled = embeddedContent?.performKeyEquivalent(with: event) ?? false
            report["embedded_shortcut_routing_checked"] = handled && outline.selectedRow == 1
        }
        report["tree_has_keyboard_focus"] = window?.firstResponder === outline
        report["selected_row"] = outline.selectedRow
        report["selected_name"] = selectedTreeNode?.name ?? ""
        report["panel_accessibility_role"] = embeddedContent?.accessibilityRole()?.rawValue ?? ""
        if let preview = preview, let view = embeddedContent {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: preview))
            }
        }
        return report
    }

    func stopEmbedded() {
        timer?.invalidate(); timer = nil
        speech.stop(); voiceOverObservation = nil
        bridge?.close(); bridge = nil
        embeddedContent?.removeFromSuperview()
        embeddedContent = nil; window = nil
    }

    private func syncToolbar(_ visible: Bool) {
        guard selfTestPath == nil, bridge != nil, toolbarVisible != visible else { return }
        toolbarVisible = visible
        bridge?.request("panel-state", parameters: ["visible": visible]) { _ in }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window != nil { syncToolbar(window.isVisible) }
    }
    func applicationDidResignActive(_ notification: Notification) { syncToolbar(false) }

    private func argument(_ name: String) -> String? {
        if let embeddedOptions = embeddedOptions { return embeddedOptions[name] }
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        selfTestPath = argument("--self-test")
        NSApp.setActivationPolicy(.accessory)
        hostPID = argument("--rdk-pid").flatMap(Int32.init)
        if selfTestPath == nil {
            queuedCommand = (argument("--initial-command") ?? "show", (argument("--items") ?? "").split(separator: ",").map(String.init))
            integration = IntegrationChannel(port: argument("--port") ?? "20500") { [weak self] command, items in
                self?.receiveCommand(command, items: items)
            }
            hostObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self = self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier == self.hostPID else { return }
                NSApp.terminate(nil)
            }
        }
        makeMenus()
        makeWindow()
        if selfTestPath == nil && ProcessInfo.processInfo.environment["VOICEACCESS_DIAGNOSTICS"] == "1" { startNavigationTrace() }
        speech.onStarted = { [weak self] text in self?.lastSpoken = text }
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applySpeechOutput() }
        }
        let bundle = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let python = argument("--python") ?? "/usr/bin/python3"
        let script = argument("--bridge") ?? bundle.appendingPathComponent("_voiceaccess/bridge.py").path
        do {
            bridge = try APIBridge(python: python, script: script, port: argument("--port") ?? "20500")
            bridge?.onFailure = { [weak self] message in self?.status.stringValue = self?.t(message) ?? message }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.poll() }
        } catch { showError("\(t("Could not start the connection")): \(error.localizedDescription)") }
        if selfTestPath == nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeMain()
            outline.focusSelection()
            syncToolbar(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.traceNavigation("opened") }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); speech.stop(); bridge?.close(); voiceOverObservation = nil; integration = nil
        if let token = hostObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        try? traceHandle?.close()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        returnToRoboDK(nil)
        return false
    }

    private func showPanel() {
        guard selfTestPath == nil else { return }
        if embeddedOptions != nil {
            embeddedVisibility?(true)
            window = embeddedContent?.window
            guard window != nil else { return }
            outline.focusSelection()
            syncToolbar(true)
            return
        }
        setReaderActive(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeMain()
        outline.focusSelection()
        syncToolbar(true)
    }

    func receiveCommand(_ command: String, items: [String]) {
        if command == "hide" {
            returnToRoboDK(nil)
            return
        }
        if command == "silence" {
            silence(nil)
            narrate.state = .off
            return
        }
        queuedCommand = (command, items)
        showPanel()
        if !refreshing { refresh() }
    }

    private func button(_ title: String, _ selector: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSButton {
        let control = NSButton(title: title, target: self, action: selector)
        control.bezelStyle = .rounded
        control.keyEquivalent = key
        control.keyEquivalentModifierMask = modifiers
        control.setAccessibilityLabel(title)
        control.cell?.setAccessibilityLabel(title)
        controls.append(control)
        localizedButtons.append((control, title))
        return control
    }

    private func t(_ text: String) -> String { ui[text] ?? text }
    private func label(_ text: String, wrapping: Bool = false) -> NSTextField {
        let field = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        localizedLabels.append((field, text))
        return field
    }

    private func makeMenus() {
        let bar = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu()
        let quit = appMenu.addItem(withTitle: "Quit VoiceAccess", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        localizedMenus.append((quit, "Quit VoiceAccess"))
        application.submenu = appMenu
        bar.addItem(application)
        let actions = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        localizedMenus.append((actions, "Actions"))
        let menu = NSMenu(title: "Actions")
        for (title, selector, key) in [
            ("Find an item", #selector(focusSearch(_:)), "f"),
            ("Focus station tree", #selector(focusTree(_:)), "t"),
            ("Previous item", #selector(previousItem(_:)), "\u{f700}"),
            ("Next item", #selector(nextItem(_:)), "\u{f701}"),
            ("Expand item", #selector(expandItem(_:)), "\u{f703}"),
            ("Collapse item", #selector(collapseItem(_:)), "\u{f702}"),
            ("Refresh station", #selector(refreshAction(_:)), "r"),
            ("Read details", #selector(readCurrent(_:)), "l"),
            ("Read RoboDK selection", #selector(readSelection(_:)), "s"),
            ("Simulate selected program", #selector(simulate(_:)), "\r"),
            ("Stop simulation", #selector(stopSimulation(_:)), "."),
            ("Slower", #selector(slower(_:)), "["),
            ("Faster", #selector(faster(_:)), "]"),
            ("Back to RoboDK", #selector(returnToRoboDK(_:)), "b"),
        ] {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.target = self
            localizedMenus.append((item, title))
        }
        actions.submenu = menu
        bar.addItem(actions)
        if embeddedOptions != nil { embeddedMenu = menu }
        else { NSApp.mainMenu = bar }
    }

    private func makeWindow() {
        let panel = VoiceAccessPanel(contentRect: NSRect(x: 0, y: 0, width: 1010, height: 880), styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        window = panel
        window.title = "VoiceAccess — RoboDK"
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
        window.delegate = self
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 860, height: 800)
        window.center()
        let content = window.contentView!
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = embeddedOptions == nil ? 12 : 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        let inset: CGFloat = embeddedOptions == nil ? 20 : 12
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),
        ])
        let heading = label("Listen to your station")
        heading.font = .systemFont(ofSize: embeddedOptions == nil ? 25 : 19, weight: .semibold)
        stack.addArrangedSubview(heading)
        let toolbar = NSStackView(views: [
            button("Refresh", #selector(refreshAction(_:))),
            button("RoboDK selection", #selector(readSelection(_:))),
            button("Read details", #selector(readCurrent(_:))),
            button("Repeat", #selector(repeatLast(_:))),
            button("Silence", #selector(silence(_:)), key: "\u{1b}", modifiers: []),
            button("Back to RoboDK", #selector(returnToRoboDK(_:))),
        ])
        toolbar.spacing = 8
        if embeddedOptions != nil {
            let buttons = toolbar.arrangedSubviews
            buttons.forEach { toolbar.removeArrangedSubview($0); $0.removeFromSuperview() }
            for offset in stride(from: 0, to: buttons.count, by: 2) {
                let row = NSStackView(views: Array(buttons[offset..<min(offset + 2, buttons.count)]))
                row.spacing = 8
                stack.addArrangedSubview(row)
            }
        } else { stack.addArrangedSubview(toolbar) }
        execution.font = .systemFont(ofSize: 17, weight: .semibold)
        execution.maximumNumberOfLines = 3
        stack.addArrangedSubview(execution)
        execution.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 13)
        status.setAccessibilityLabel("Status and last announcement")
        status.maximumNumberOfLines = 2
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        search.placeholderString = "Find an item or instruction"
        search.setAccessibilityLabel("Find an item or instruction")
        search.delegate = self
        let foldButtons = [button("Expand item", #selector(expandItem(_:))), button("Collapse item", #selector(collapseItem(_:)))]
        let searchRow = NSStackView(views: [search] + (embeddedOptions == nil ? foldButtons : []))
        searchRow.spacing = 8
        stack.addArrangedSubview(searchRow)
        searchRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: embeddedOptions == nil ? 240 : 180).isActive = true
        if embeddedOptions != nil {
            let row = NSStackView(views: foldButtons)
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("element"))
        column.title = "Items and instructions"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 28
        outline.indentationPerLevel = 18
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = false
        outline.usesAlternatingRowBackgroundColors = true
        outline.setAccessibilityLabel("Station tree. Items and instructions")
        outline.setAccessibilityHelp("Use VO+Shift+Down to interact. Command+Down and Command+Up select the next and previous item from anywhere in this panel.")
        let context = NSMenu()
        for (title, selector) in [("Read details", #selector(readCurrent(_:))), ("Expand item", #selector(expandItem(_:))), ("Collapse item", #selector(collapseItem(_:))), ("Simulate program", #selector(simulate(_:)))] {
            let item = context.addItem(withTitle: title, action: selector, keyEquivalent: "")
            item.target = self
            localizedMenus.append((item, title))
        }
        outline.menu = context
        let treeScroll = NSScrollView()
        treeScroll.hasVerticalScroller = true
        treeScroll.borderType = .bezelBorder
        treeScroll.documentView = outline
        stack.addArrangedSubview(treeScroll)
        treeScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        treeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: embeddedOptions == nil ? 225 : 120).isActive = true

        let title = label("Selected item details")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(title)
        details.isEditable = false
        details.isSelectable = true
        details.isRichText = false
        details.font = .systemFont(ofSize: 15)
        details.textContainerInset = NSSize(width: 10, height: 10)
        details.setAccessibilityLabel("Item description, coordinates and context")
        let detailScroll = NSScrollView()
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder
        detailScroll.documentView = details
        stack.addArrangedSubview(detailScroll)
        detailScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: embeddedOptions == nil ? 145 : 80).isActive = true
        detailScroll.heightAnchor.constraint(equalTo: treeScroll.heightAnchor, multiplier: 0.65).isActive = true

        follow.state = .on
        narrate.state = .on
        outputMode.addItems(withTitles: ["Automatic", "VoiceOver", "Own voice"])
        outputMode.menu?.autoenablesItems = false
        outputMode.target = self
        outputMode.action = #selector(outputChanged(_:))
        narrate.target = self
        narrate.action = #selector(narrationChanged(_:))
        localizedButtons += [(follow, "Follow RoboDK selection"), (narrate, "Narrate simulation")]
        let output = NSStackView(views: [label("Speech output"), outputMode])
        output.spacing = 8
        let options = NSStackView(views: embeddedOptions == nil ? [label("Speech output"), outputMode, follow, narrate] : [output, follow, narrate])
        if embeddedOptions != nil { options.orientation = .vertical; options.alignment = .leading }
        options.spacing = embeddedOptions == nil ? 20 : 6
        stack.addArrangedSubview(options)

        rateSlider.target = self
        rateSlider.action = #selector(rateChanged(_:))
        rateSlider.isContinuous = false
        rateSlider.setAccessibilityLabel("Speech rate")
        rateSlider.setAccessibilityHelp("Own voice only; VoiceOver uses its own speech rate.")
        rateSlider.widthAnchor.constraint(equalToConstant: embeddedOptions == nil ? 210 : 180).isActive = true
        rateValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        rateValue.setContentHuggingPriority(.required, for: .horizontal)
        let rateRow = NSStackView(views: [
            label("Speech rate"), button("Slower", #selector(slower(_:))), rateSlider,
            button("Faster", #selector(faster(_:))), rateValue,
            button("Test voice", #selector(testVoice(_:))),
        ])
        rateRow.spacing = 8
        if embeddedOptions != nil {
            let controls = rateRow.arrangedSubviews
            controls.forEach { rateRow.removeArrangedSubview($0); $0.removeFromSuperview() }
            let top = NSStackView(views: [controls[0], controls[1], controls[3]])
            top.spacing = 8
            stack.addArrangedSubview(top)
            stack.addArrangedSubview(rateSlider)
            let bottom = NSStackView(views: [rateValue, controls[5]])
            bottom.spacing = 8
            stack.addArrangedSubview(bottom)
        } else { stack.addArrangedSubview(rateRow) }
        voiceInfo.font = .systemFont(ofSize: 12)
        voiceInfo.textColor = .secondaryLabelColor
        stack.addArrangedSubview(voiceInfo)
        voiceInfo.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let playback = NSStackView(views: [
            button("Simulate program", #selector(simulate(_:))),
            button("Stop simulation", #selector(stopSimulation(_:))),
        ])
        playback.spacing = 10
        stack.addArrangedSubview(playback)
        let help = label("⌘↑↓ navigate · ⌘→ expand · ⌘← collapse · ⌘T tree · ⌘F find · ⌘L details\nVO+Shift+M item menu · ⌘B back to RoboDK · Esc silence.", wrapping: true)
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        stack.addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func applyConfiguration(_ config: [String: Any]) {
        let newLanguage = config["language"] as? String ?? "en"
        if language != newLanguage { speech.stop(); lastSpoken = "" }
        language = newLanguage
        robodkLanguage = config["robodk_language"] as? String ?? language
        ui = config["ui"] as? [String: String] ?? [:]
        speech.voice = config["voice"] as? String
        speech.rate = max(100, min(350, config["speech_rate"] as? Int ?? 175))
        speechOutput = SpeechOutputMode(rawValue: config["speech_output"] as? String ?? "automatic") ?? .automatic
        voiceTest = config["voice_test"] as? String ?? ""
        for (control, key) in localizedButtons {
            control.title = t(key)
            control.setAccessibilityLabel(t(key))
            control.cell?.setAccessibilityLabel(t(key))
        }
        for (field, key) in localizedLabels { field.stringValue = t(key) }
        for (item, key) in localizedMenus { item.title = t(key) }
        search.placeholderString = t("Find an item or instruction")
        search.setAccessibilityLabel(t("Find an item or instruction"))
        search.cell?.setAccessibilityLabel(t("Find an item or instruction"))
        outline.setAccessibilityLabel(t("Station tree. Items and instructions"))
        outline.setAccessibilityHelp(t("Use VO+Shift+Down to interact. Command+Down and Command+Up select the next and previous item from anywhere in this panel."))
        outline.outlineTableColumn?.title = t("Items and instructions")
        status.setAccessibilityLabel(t("Status and last announcement"))
        status.cell?.setAccessibilityLabel(t("Status and last announcement"))
        execution.cell?.setAccessibilityLabel(t("Execution progress"))
        execution.stringValue = t("No simulation running.")
        details.setAccessibilityLabel(t("Item description, coordinates and context"))
        rateSlider.setAccessibilityLabel(t("Speech rate"))
        rateSlider.setAccessibilityHelp(t("Own voice only; VoiceOver uses its own speech rate."))
        rateSlider.cell?.setAccessibilityLabel(t("Speech rate"))
        rateSlider.cell?.setAccessibilityHelp(t("Own voice only; VoiceOver uses its own speech rate."))
        for (index, key) in ["Automatic", "VoiceOver", "Own voice"].enumerated() { outputMode.item(at: index)?.title = t(key) }
        outputMode.setAccessibilityLabel(t("Speech output"))
        outputMode.cell?.setAccessibilityLabel(t("Speech output"))
        applySpeechOutput()
        updateRateDisplay()
    }

    private func applySpeechOutput(voiceOverState: Bool? = nil) {
        voiceOverRunning = voiceOverState ?? NSWorkspace.shared.isVoiceOverEnabled
        let next = speechOutput.usesOwnVoice(voiceOverRunning: voiceOverRunning)
        if usingOwnVoice != next || voiceOverRunning { speech.stop() }
        usingOwnVoice = next
        outputMode.selectItem(at: voiceOverRunning ? 1 : speechOutput == .automatic ? 0 : speechOutput == .voiceOver ? 1 : 2)
        outputMode.item(at: 2)?.isEnabled = !voiceOverRunning
        rateSlider.isEnabled = usingOwnVoice
        for (control, key) in localizedButtons where key == "Slower" || key == "Faster" { control.isEnabled = usingOwnVoice }
        for (item, key) in localizedMenus where key == "Slower" || key == "Faster" { item.isEnabled = usingOwnVoice }
        let name = ["en": "English", "ca": "Català", "es": "Español"][language] ?? language
        let languageInfo = robodkLanguage.hasPrefix(language) ? name : "\(robodkLanguage) → \(name)"
        let output = usingOwnVoice ? (speech.voice ?? "macOS") : "VoiceOver"
        let explanation = usingOwnVoice ? t("Speech rate controls the local voice.") : voiceOverRunning ? t("VoiceOver uses its own voice and speech rate.") : t("VoiceOver is off. Turn it on or choose Own voice.")
        voiceInfo.stringValue = "RoboDK: \(languageInfo) · \(output) · \(explanation)"
    }

    private func updateRateDisplay() {
        rateSlider.integerValue = speech.rate
        let value = t("{rate} words per minute").replacingOccurrences(of: "{rate}", with: String(speech.rate))
        rateValue.stringValue = value
        rateValue.setAccessibilityLabel(value)
        rateSlider.setAccessibilityValueDescription(value)
        rateSlider.cell?.setAccessibilityValueDescription(value)
    }

    private var settingsURL: URL {
        if selfTestPath != nil, let path = argument("--settings-path") { return URL(fileURLWithPath: path) }
        return defaultSettingsURL
    }

    private var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RoboDKVoiceAccess/settings.json")
    }

    private func changeRate(to value: Int, persist: Bool = true, speak: Bool = true) {
        speech.stop()
        speech.rate = max(100, min(350, value))
        updateRateDisplay()
        if persist { saveSettings() }
        if speak { announce(rateValue.stringValue) }
    }

    private func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var settings = (try? Data(contentsOf: settingsURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            settings["speech_rate"] = speech.rate
            settings["speech_output"] = speechOutput.rawValue
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
        } catch { status.stringValue = "Could not save the speech settings: \(error.localizedDescription)" }
    }

    private func setDetails(_ result: [String: Any]) {
        details.string = result["text"] as? String ?? ""
        detailSpeech = result["spoken_text"] as? String ?? details.string
    }

    private func shownChildren(_ item: Any?) -> [StationNode] {
        guard let node = item as? StationNode else { return visibleRoots }
        return visibleChildren[node.id] ?? []
    }
    private func filterTree() {
        rebuildingTree = true
        defer { rebuildingTree = false; updateTreeActions() }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleChildren = [:]
        func visit(_ node: StationNode, _ ancestorMatches: Bool) -> Bool {
            let matches = ancestorMatches || query.isEmpty || node.label.localizedCaseInsensitiveContains(query)
            let children = node.children.filter { visit($0, matches) }
            visibleChildren[node.id] = children
            return matches || !children.isEmpty
        }
        visibleRoots = roots.filter { visit($0, false) }
        outline.reloadData()
        visibleRoots.forEach { outline.expandItem($0, expandChildren: true) }
        if query.isEmpty {
            for id in collapsedNodes {
                if let node = nodes[id] { outline.collapseItem(node) }
            }
        }
        NSAccessibility.post(element: outline, notification: .layoutChanged)
    }
    func controlTextDidChange(_ notification: Notification) { filterTree() }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { shownChildren(item).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { shownChildren(item)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !shownChildren(item).isEmpty }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        embeddedOptions == nil ? nil : EmbeddedStationRowView()
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! StationNode
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: node.label)
        text.font = .systemFont(ofSize: 14)
        text.lineBreakMode = .byTruncatingTail
        text.setAccessibilityLabel(node.accessibilityLabel)
        // AppKit exposes the cell as AXStaticText. Expand punctuation there,
        // while keeping the visible text and the actual station name intact.
        text.cell?.setAccessibilityLabel(node.accessibilityLabel)
        text.cell?.setAccessibilityValue(node.accessibilityLabel)
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard outline.selectedRow >= 0, let node = outline.item(atRow: outline.selectedRow) as? StationNode else { return }
        selectedID = node.id
        updateTreeActions()
        outline.notifyAccessibilitySelection()
        if applyingSelection || !readerActive { return }
        bridge?.request("detail", itemID: node.id) { [weak self] response in
            guard let self = self, self.selectedID == node.id else { return }
            if let result = self.result(response) { self.setDetails(result) }
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if !rebuildingTree, let node = notification.userInfo?["NSObject"] as? StationNode { collapsedNodes.remove(node.id) }
        updateTreeActions()
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        if !rebuildingTree, let node = notification.userInfo?["NSObject"] as? StationNode { collapsedNodes.insert(node.id) }
        updateTreeActions()
    }

    private var selectedTreeNode: StationNode? {
        guard outline.selectedRow >= 0 else { return nil }
        return outline.item(atRow: outline.selectedRow) as? StationNode
    }
    private func canExpand(_ expanded: Bool) -> Bool {
        guard let node = selectedTreeNode, outline.isExpandable(node) else { return false }
        return outline.isItemExpanded(node) != expanded
    }
    private func updateTreeActions() {
        for (control, key) in localizedButtons {
            if key == "Expand item" { control.isEnabled = canExpand(true) }
            if key == "Collapse item" { control.isEnabled = canExpand(false) }
            if key == "Simulate program" { control.isEnabled = selectedTreeNode?.type == 8 && !simulationAdmission.pending && runningPrograms.isEmpty }
        }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Keep the keyboard commands available as selection/expansion changes;
        // the actions themselves guard leaves and unchanged states. The context
        // menu and buttons additionally reflect whether expansion is possible.
        if item.action == #selector(expandItem(_:)) { return item.menu === outline.menu ? canExpand(true) : true }
        if item.action == #selector(collapseItem(_:)) { return item.menu === outline.menu ? canExpand(false) : true }
        if item.action == #selector(simulate(_:)) { return selectedTreeNode?.type == 8 && !simulationAdmission.pending && runningPrograms.isEmpty }
        return true
    }
    @objc private func expandItem(_ sender: Any?) { setItemExpanded(true) }
    @objc private func collapseItem(_ sender: Any?) { setItemExpanded(false) }
    private func setItemExpanded(_ expanded: Bool) {
        guard canExpand(expanded), let row = outline.accessibleRow(at: outline.selectedRow) else { return }
        row.setAccessibilityDisclosed(expanded)
        outline.focusSelection()
        if usingOwnVoice { announce(t(expanded ? "Expanded." : "Collapsed.") + " " + row.node.accessibilityLabel, priority: .selection) }
        updateTreeActions()
    }

    private func result(_ response: [String: Any], announceError: Bool = true) -> [String: Any]? {
        if response["ok"] as? Bool == true { return response["result"] as? [String: Any] }
        let message = t(response["error"] as? String ?? "Could not complete the action.")
        status.stringValue = message
        status.cell?.setAccessibilityValue(response["spoken_error"] as? String ?? message)
        if announceError { announce(response["spoken_error"] as? String ?? message) }
        return nil
    }
    private func showError(_ text: String) { status.stringValue = text; details.string = text }

    private func refresh() {
        guard readerActive, !refreshing else { return }
        refreshing = true
        bridge?.request("snapshot") { [weak self] response in
            guard let self = self else { return }
            self.refreshing = false
            guard let result = self.result(response) else { return }
            if self.hostPID == nil, let pid = result["host_pid"] as? Int { self.hostPID = pid_t(pid) }
            self.applyConfiguration(result["configuration"] as? [String: Any] ?? [:])
            let previousID = self.selectedID
            let newStationID = result["station_id"] as? String ?? ""
            if self.stationID != newStationID { self.speech.stopAutomatic(); self.runningPrograms = []; self.collapsedNodes.removeAll() }
            self.roots = (result["nodes"] as? [[String: Any]] ?? []).map(StationNode.init)
            self.nodes = [:]
            func index(_ node: StationNode) { self.nodes[node.id] = node; node.children.forEach(index) }
            self.roots.forEach(index)
            self.stationID = newStationID
            self.lastRDKSelection = result["selection"] as? [String] ?? []
            self.filterTree()
            self.status.stringValue = result["message"] as? String ?? self.t("Station loaded.")
            self.status.cell?.setAccessibilityValue(result["spoken_message"] as? String ?? self.status.stringValue)
            let candidate = previousID ?? self.lastRDKSelection.first ?? self.roots.first?.id
            if let id = candidate, let node = self.nodes[id] {
                let row = self.outline.row(forItem: node)
                if row >= 0 { self.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
            if self.selfTestPath != nil { self.finishSelfTest() }
            else if let (command, identifiers) = self.queuedCommand {
                self.queuedCommand = nil
                self.requestSelection(speak: command == "read-selection", identifiers: identifiers, focus: true)
            }
        }
    }

    private func poll() {
        guard readerActive, selfTestPath == nil, !polling, !refreshing, !stationID.isEmpty else { return }
        polling = true
        bridge?.request("poll") { [weak self] response in
            guard let self = self else { return }
            self.polling = false
            guard let result = self.result(response, announceError: false) else { return }
            if result["needs_refresh"] as? Bool == true { self.refresh(); return }
            let progress = result["progress"] as? [[String: Any]] ?? []
            let events = result["events"] as? [[String: Any]] ?? []
            let running = result["running"] as? [String] ?? []
            self.showProgress(progress, events: events)
            let selection = result["selection"] as? [String] ?? []
            if selection != self.lastRDKSelection {
                self.lastRDKSelection = selection
                if self.follow.state == .on && (self.embeddedOptions != nil || !NSApp.isActive) {
                    // Simulation also changes RoboDK's selection. Do not read a
                    // full item description over its movement narration.
                    self.requestSelection(speak: running.isEmpty && self.runningPrograms.isEmpty, automatic: true)
                }
            }
            if let id = self.selectedID, self.nodes[id]?.type == 8, running.contains(id) != self.runningPrograms.contains(id) {
                self.bridge?.request("detail", itemID: id) { [weak self] response in
                    guard let self = self, self.selectedID == id,
                          let detail = self.result(response, announceError: false) else { return }
                    self.setDetails(detail)
                }
            }
            self.runningPrograms = running
            self.updateTreeActions()
            for event in events {
                let text = event["text"] as? String ?? ""
                self.status.stringValue = text
                self.status.cell?.setAccessibilityValue(event["spoken_text"] as? String ?? text)
                if self.narrate.state == .on {
                    self.announce(event["spoken_text"] as? String ?? text, automatic: true)
                }
            }
        }
    }

    private func showProgress(_ progress: [[String: Any]], events: [[String: Any]] = []) {
        if !progress.isEmpty {
            execution.stringValue = progress.compactMap { $0["text"] as? String }.joined(separator: "\n")
            execution.cell?.setAccessibilityValue(progress.compactMap { $0["spoken_text"] as? String }.joined(separator: "\n"))
        } else if let end = events.last(where: { $0["kind"] as? String == "end" }) {
            execution.stringValue = end["progress_text"] as? String ?? end["text"] as? String ?? ""
            execution.cell?.setAccessibilityValue(end["progress_spoken_text"] as? String ?? end["spoken_text"] as? String ?? execution.stringValue)
        }
    }

    private func announce(_ text: String, automatic: Bool = false, priority: LocalSpeech.AutomaticPriority = .execution) {
        guard readerActive, selfTestPath == nil, !embeddedChecksRunning, !text.isEmpty else { return }
        if voiceOverRunning != NSWorkspace.shared.isVoiceOverEnabled { applySpeechOutput() }
        if usingOwnVoice {
            if automatic { speech.narrate(text, priority: priority) }
            else { speech.speak(text) }
        }
        else {
            lastSpoken = text
            NSAccessibility.post(element: window!, notification: .announcementRequested, userInfo: [
                .announcement: text,
                .priority: (automatic ? NSAccessibilityPriorityLevel.low : NSAccessibilityPriorityLevel.high).rawValue,
            ])
        }
    }
    private func requestSelection(speak: Bool, automatic: Bool = false, identifiers: [String]? = nil, focus: Bool = false) {
        guard readerActive else { return }
        var parameters: [String: Any] = [:]
        if let identifiers = identifiers { parameters["item_ids"] = identifiers }
        bridge?.request("selection", parameters: parameters) { [weak self] response in
            guard let self = self, let result = self.result(response, announceError: !automatic) else { return }
            self.setDetails(result)
            if focus {
                self.search.stringValue = ""
                self.filterTree()
                let id = (result["node_ids"] as? [String])?.first ?? self.roots.first?.id
                if let id = id, let node = self.nodes[id] {
                    let row = self.outline.row(forItem: node)
                    if row >= 0 {
                        self.applyingSelection = true
                        self.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        self.applyingSelection = false
                        self.outline.scrollRowToVisible(row)
                    }
                    if (result["node_ids"] as? [String] ?? []).isEmpty, !speak {
                        self.bridge?.request("detail", itemID: node.id) { [weak self] response in
                            guard let self = self, self.selectedID == node.id, let detail = self.result(response) else { return }
                            self.setDetails(detail)
                        }
                    }
                }
                self.outline.focusSelection()
            }
            if speak, let name = result["spoken_selection_name"] as? String {
                self.announce(name, automatic: automatic, priority: .selection)
            }
        }
    }

    @objc private func refreshAction(_ sender: Any?) { refresh() }
    @objc private func focusSearch(_ sender: Any?) { window.makeFirstResponder(search) }
    @objc private func focusTree(_ sender: Any?) { outline.focusSelection() }
    private func moveItem(by offset: Int) {
        guard outline.numberOfRows > 0 else { return }
        let target = outline.selectedRow < 0 ? 0 : max(0, min(outline.numberOfRows - 1, outline.selectedRow + offset))
        guard outline.selectAccessibleRow(target), let node = outline.item(atRow: target) as? StationNode else { return }
        // VoiceOver receives the row's focus/selection notification. Sending a
        // second announcement here would repeat or interrupt that same label.
        if usingOwnVoice { announce(node.accessibilityLabel, priority: .selection) }
        else { lastSpoken = node.accessibilityLabel }
    }
    @objc private func previousItem(_ sender: Any?) { moveItem(by: -1) }
    @objc private func nextItem(_ sender: Any?) { moveItem(by: 1) }
    @objc private func readSelection(_ sender: Any?) { requestSelection(speak: true) }
    @objc private func readCurrent(_ sender: Any?) { announce(detailSpeech) }
    @objc private func repeatLast(_ sender: Any?) { announce(lastSpoken) }
    @objc private func silence(_ sender: Any?) { speech.stop() }
    @objc private func outputChanged(_ sender: Any?) {
        speech.stop()
        speechOutput = outputMode.indexOfSelectedItem == 0 ? .automatic : outputMode.indexOfSelectedItem == 1 ? .voiceOver : .ownVoice
        applySpeechOutput()
        saveSettings()
    }
    @objc private func returnToRoboDK(_ sender: Any?) {
        guard selfTestPath == nil else { return }
        setReaderActive(false)
        if embeddedOptions != nil {
            embeddedVisibility?(false)
            syncToolbar(false)
            return
        }
        window.orderOut(nil)
        syncToolbar(false)
        if let pid = hostPID { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
    }
    @objc private func narrationChanged(_ sender: Any?) {
        if narrate.state == .off { speech.stopAutomatic() }
    }
    @objc private func rateChanged(_ sender: Any?) { changeRate(to: rateSlider.integerValue) }
    @objc private func slower(_ sender: Any?) { changeRate(to: speech.rate - 10) }
    @objc private func faster(_ sender: Any?) { changeRate(to: speech.rate + 10) }
    @objc private func testVoice(_ sender: Any?) {
        guard selfTestPath == nil else { return }
        announce(voiceTest)
    }
    @objc private func simulate(_ sender: Any?) {
        guard readerActive else { return }
        guard let identifier = selectedID else { announce(t("Select a simulation program in the VoiceAccess tree.")); return }
        guard simulationAdmission.begin(running: !runningPrograms.isEmpty) else { return }
        updateTreeActions()
        bridge?.request("simulate", itemID: identifier) { [weak self] response in
            guard let self = self else { return }
            self.simulationAdmission.completed()
            self.updateTreeActions()
            if let result = self.result(response), result["started"] as? Bool != false {
                self.announce(result["spoken_text"] as? String ?? result["text"] as? String ?? "")
            }
        }
    }
    @objc private func stopSimulation(_ sender: Any?) {
        bridge?.request("stop") { [weak self] response in
            guard let self = self, let result = self.result(response) else { return }
            self.announce(result["spoken_text"] as? String ?? result["text"] as? String ?? "")
        }
    }

    private func checkOutlineNavigation(program: StationNode) -> [String: Any] {
        let rows = outline.accessibilityRows() ?? []
        guard rows.count > 1, let first = rows.first as? StationAccessibilityRow,
              let second = rows[1] as? StationAccessibilityRow else { return [:] }
        let legacy = outline.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: "AXRows")?.takeUnretainedValue() as? [Any] ?? []
        let bridgeMatches = legacy.count == rows.count && legacy[1] as? StationAccessibilityRow === second
        outline.setAccessibilitySelectedRows([first])
        let rootSelected = outline.selectedRow == 0 && window.firstResponder === outline
        outline.setAccessibilitySelectedRows([second])
        let axSelection = outline.selectedRow == 1 && selectedID == second.node.id
        func key(_ character: String, _ keyCode: UInt16, command: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!
        }
        window.sendEvent(key("\u{f700}", 126))
        let up = outline.selectedRow == 0
        window.sendEvent(key("\u{f701}", 125))
        let down = outline.selectedRow == 1
        outline.setAccessibilitySelectedRows([first])
        window.makeFirstResponder(search)
        let nextHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f701}", 125, command: true)) ?? false
        let nextWorks = nextHandled && outline.selectedRow == 1 && selectedID == second.node.id
        window.makeFirstResponder(search)
        let previousHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f700}", 126, command: true)) ?? false
        let previousWorks = previousHandled && outline.selectedRow == 0
        window.makeFirstResponder(search)
        let focusHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("t", 17, command: true)) ?? false
        let focusWorks = focusHandled && window.firstResponder === outline
        let collapseHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f702}", 123, command: true)) ?? false
        let collapsed = collapseHandled && outline.numberOfRows == 1 && collapsedNodes.contains(first.node.id)
        filterTree()
        let collapsePreserved = outline.numberOfRows == 1
        search.stringValue = program.name
        filterTree()
        let searchFindsCollapsedDescendant = outline.numberOfRows > 1
        search.stringValue = ""
        filterTree()
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let expandHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f703}", 124, command: true)) ?? false
        let expanded = expandHandled && outline.isItemExpanded(first.node) && outline.numberOfRows > 1 &&
            first.node.children.allSatisfy { outline.row(forItem: $0) >= 0 } && !collapsedNodes.contains(first.node.id)
        filterTree()
        let programRow = outline.row(forItem: program)
        if programRow >= 0 { outline.selectRowIndexes(IndexSet(integer: programRow), byExtendingSelection: false) }
        let foldProgramHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f702}", 123, command: true)) ?? false
        let programFocusPreserved = foldProgramHandled && programRow > 0 &&
            outline.selectedRow == outline.row(forItem: program) && selectedID == program.id &&
            window.firstResponder === outline && !outline.isItemExpanded(program)
        let followingRow = outline.selectedRow + 1
        let afterFoldNextHandled = (embeddedMenu ?? NSApp.mainMenu)?.performKeyEquivalent(with: key("\u{f701}", 125, command: true)) ?? false
        let navigationContinuesAfterFold = afterFoldNextHandled &&
            outline.selectedRow == min(followingRow, outline.numberOfRows - 1)
        _ = outline.selectAccessibleRow(outline.row(forItem: program))
        expandItem(nil)
        let programExpandFocusPreserved = outline.selectedRow == outline.row(forItem: program) &&
            selectedID == program.id && window.firstResponder === outline
        let simulateItem = outline.menu?.items.first { $0.action == #selector(simulate(_:)) }
        let programSimulationAvailable = simulateItem.map { validateMenuItem($0) && $0.target as? VoiceAccessController === self } ?? false
        outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let leafSimulationDisabled = simulateItem.map { !validateMenuItem($0) } ?? false
        return [
            "outline_accessible_rows": rows.count,
            "outline_first_accessible_label": first.accessibilityLabel() ?? "",
            "outline_second_accessible_label": second.accessibilityLabel() ?? "",
            "outline_public_and_attribute_rows_match": bridgeMatches,
            "outline_ax_selection_updates_model_checked": rootSelected && axSelection,
            "outline_plain_arrow_navigation_checked": up && down,
            "global_item_navigation_shortcuts_checked": nextWorks && previousWorks,
            "focus_tree_shortcut_checked": focusWorks,
            "expand_collapse_shortcuts_checked": collapsed && expanded,
            "non_root_fold_preserves_focus_and_navigation": programFocusPreserved && navigationContinuesAfterFold && programExpandFocusPreserved,
            "collapse_command_handled": collapseHandled,
            "collapse_command_collapsed_root": collapsed,
            "expand_command_handled": expandHandled,
            "expand_command_shows_children": expanded,
            "collapsed_state_preserved_after_filter_refresh": collapsePreserved && searchFindsCollapsedDescendant,
            "tree_context_menu_labels": outline.menu?.items.map(\.title) ?? [],
            "context_simulation_available_for_program_only": programSimulationAvailable && leafSimulationDisabled,
        ]
    }

    private func startNavigationTrace() {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/RoboDKVoiceAccess/navigation.jsonl")
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: path)
        traceHandle = try? FileHandle(forWritingTo: path)
        outline.trace = { [weak self] phase in self?.traceNavigation(phase) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if (123...126).contains(event.keyCode) {
                self?.traceNavigation("app.key.\(event.keyCode).modifiers.\(event.modifierFlags.rawValue)")
                DispatchQueue.main.async { self?.traceNavigation("app.key.after") }
            }
            return event
        }
        traceNavigation("started")
    }

    private func traceNavigation(_ phase: String) {
        guard selfTestPath == nil, traceCount < 500, let handle = traceHandle else { return }
        let now = Date()
        if phase == "ax.rows", now.timeIntervalSince(lastAXTrace) < 0.5 { return }
        if phase == "ax.rows" { lastAXTrace = now }
        traceCount += 1
        let event: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: now), "phase": phase,
            "app_active": NSApp.isActive, "window_key": window.isKeyWindow,
            "window_main": window.isMainWindow, "window_visible": window.isVisible,
            "can_become_main": window.canBecomeMain,
            "first_responder": window.firstResponder.map { String(describing: type(of: $0)) } ?? "none",
            "tree_has_keyboard_focus": window.firstResponder === outline,
            "rows": outline.numberOfRows, "selected_row": outline.selectedRow,
            "tree_width": outline.frame.width, "tree_height": outline.frame.height,
            "viewport_width": outline.visibleRect.width, "viewport_height": outline.visibleRect.height,
            "voiceover_running": NSWorkspace.shared.isVoiceOverEnabled,
        ]
        if var data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) {
            data.append(10)
            try? handle.write(contentsOf: data)
        }
    }

    private func finishSelfTest() {
        guard let path = selfTestPath else { return }
        let program = nodes.values.first(where: { $0.name == "05 Programa de prova" }) ?? nodes.values.first(where: { $0.name == "Main" })
        guard let program = program else { showError("Self-test: no program found"); NSApp.terminate(nil); return }
        bridge?.request("detail", itemID: program.id) { [weak self] response in
            guard let self = self else { return }
            let text = (response["result"] as? [String: Any])?["text"] as? String ?? ""
            let totalRows = self.outline.numberOfRows
            let navigation = self.checkOutlineNavigation(program: program)
            self.search.stringValue = program.name
            self.filterTree()
            let row = self.outline.row(forItem: program)
            if row >= 0 { self.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            self.details.string = text
            var completionChecked = false
            if let path = self.argument("--completion-fixture"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let step = event["step"] as? Int, let total = event["total"] as? Int {
                self.showProgress([], events: [event])
                let counter = "\(step) of \(total)"
                completionChecked = self.execution.stringValue.contains(counter) && !(event["spoken_text"] as? String ?? "").contains(counter)
            }
            if let path = self.argument("--progress-fixture"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let captured = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.showProgress(captured["progress"] as? [[String: Any]] ?? [], events: captured["events"] as? [[String: Any]] ?? [])
            }
            let symbolNode = self.nodes.values.first { $0.name.contains("/") && $0.name.contains("-") }
            var symbolAXValue = ""
            var symbolDisplay = ""
            if let symbolNode = symbolNode,
               let cell = self.outlineView(self.outline, viewFor: nil, item: symbolNode) as? NSTableCellView,
               let field = cell.textField {
                symbolAXValue = field.cell?.accessibilityValue() as? String ?? ""
                symbolDisplay = field.stringValue
            }
            let initialRate = self.speech.rate
            let initialOutput = self.speechOutput
            self.speechOutput = .automatic
            self.applySpeechOutput(voiceOverState: true)
            let voiceOverAuto = !self.usingOwnVoice && !self.rateSlider.isEnabled
            self.applySpeechOutput(voiceOverState: false)
            let localAuto = self.usingOwnVoice && self.rateSlider.isEnabled
            self.speechOutput = .voiceOver
            self.applySpeechOutput(voiceOverState: false)
            let explicitVoiceOver = !self.usingOwnVoice
            self.speechOutput = .ownVoice
            self.applySpeechOutput(voiceOverState: true)
            let explicitOwnVoice = !self.usingOwnVoice && !self.outputMode.item(at: 2)!.isEnabled
            self.speechOutput = initialOutput
            self.applySpeechOutput()
            var rateControlsChecked = false
            if self.argument("--settings-path") != nil {
                self.slower(nil)
                let slowerWorks = self.speech.rate == max(100, initialRate - 10)
                self.faster(nil)
                let fasterWorks = self.speech.rate == min(350, max(100, initialRate - 10) + 10)
                self.rateSlider.integerValue = 225
                self.rateSlider.sendAction(self.rateSlider.action, to: self.rateSlider.target)
                let saved = (try? Data(contentsOf: self.settingsURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let sliderWorks = self.speech.rate == 225 && saved?["speech_rate"] as? Int == 225
                self.changeRate(to: 50)
                let minimumWorks = self.speech.rate == 100
                self.changeRate(to: 500)
                let maximumWorks = self.speech.rate == 350
                self.changeRate(to: initialRate)
                rateControlsChecked = slowerWorks && fasterWorks && sliderWorks && minimumWorks && maximumWorks
            }
            self.window.contentView?.layoutSubtreeIfNeeded()
            if let preview = self.argument("--preview"), let view = self.window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: preview)) }
            }
            var report: [String: Any] = [
                "window_title": self.window.title,
                "outline_accessibility_label": self.outline.accessibilityLabel() ?? "",
                "outline_accessibility_role": self.outline.accessibilityRole()?.rawValue ?? "",
                "rendered_row_count": totalRows,
                "filtered_row_count": self.outline.numberOfRows,
                "search_filter_checked": row >= 0 && self.outline.numberOfRows <= totalRows,
                "button_labels": self.controls.map { $0.accessibilityLabel() ?? $0.title },
                "program_name": program.name,
                "program_instruction_nodes": program.children.count,
                "program_description": text,
                "execution_progress_accessibility_label": self.execution.cell?.accessibilityLabel() ?? "",
                "execution_progress_accessibility_value": self.execution.cell?.accessibilityValue() as? String ?? "",
                "execution_progress_text": self.execution.stringValue,
                "captured_progress_replayed": self.argument("--progress-fixture") != nil,
                "auxiliary_panel": self.window.styleMask.contains(.utilityWindow),
                "panel_accepts_main_focus": self.window.canBecomeMain && self.window.canBecomeKey,
                "accessory_activation_policy": NSApp.activationPolicy() == .accessory,
                "hide_on_deactivate": (self.window as? NSPanel)?.hidesOnDeactivate ?? false,
                "speech_output": self.speechOutput.rawValue,
                "voiceover_running": self.voiceOverRunning,
                "uses_own_voice": self.usingOwnVoice,
                "voiceover_routing_matrix_checked": voiceOverAuto && localAuto && explicitVoiceOver && explicitOwnVoice,
                "voiceover_blocks_explicit_own_voice_checked": explicitOwnVoice,
                "speech_output_accessibility_label": self.outputMode.cell?.accessibilityLabel() ?? "",
                "host_pid": self.hostPID ?? 0,
                "robodk_language": self.robodkLanguage,
                "panel_language": self.language,
                "speech_voice": self.speech.voice ?? "macOS default",
                "speech_rate": self.speech.rate,
                "speech_rate_accessibility_label": self.rateSlider.cell?.accessibilityLabel() ?? "",
                "speech_rate_accessibility_value": self.rateSlider.cell?.accessibilityValueDescription() ?? "",
                "speech_rate_range": [self.rateSlider.minValue, self.rateSlider.maxValue],
                "speech_rate_controls_and_persistence_checked": rateControlsChecked,
                "speech_rate_accessibility_role": self.rateSlider.cell?.accessibilityRole()?.rawValue ?? "",
                "voice_test": self.voiceTest,
                "program_accessibility_label": program.accessibilityLabel,
                "symbol_row_accessibility_value": symbolAXValue,
                "symbol_row_display_text": symbolDisplay,
                "symbol_row_display_preserved": symbolNode != nil && symbolDisplay == symbolNode!.label,
                "native_panel_loaded": !text.isEmpty && self.outline.numberOfRows > 0,
                "manual_voiceover_validation_required": true,
                "completion_counter_visible_without_repeating_speech_checked": completionChecked,
            ]
            report.merge(navigation) { _, value in value }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}

#if !VOICEACCESS_DOCK
@main
struct VoiceAccessApplication {
    static func main() {
        func option(_ name: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: name), index+1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[index+1]
        }
        if let command = option("--request") {
            let items = (option("--items") ?? "").split(separator: ",").map(String.init)
            let accepted = IntegrationChannel.request(command: command, port: option("--port") ?? "20500", items: items)
            exit(accepted ? 0 : 69)
        }
        var lease: ReaderInstanceLease?
        if option("--self-test") == nil {
            do {
                lease = try ReaderInstanceLease(port: option("--port") ?? "20500")
                if lease == nil {
                    let command = option("--initial-command") ?? "show"
                    let items = (option("--items") ?? "").split(separator: ",").map(String.init)
                    exit(IntegrationChannel.request(command: command, port: option("--port") ?? "20500", items: items, timeout: 3) ? 0 : 69)
                }
            } catch {
                fputs("VoiceAccess could not acquire its instance lock: \(error)\n", stderr)
                exit(1)
            }
        }
        let application = NSApplication.shared
        let controller = VoiceAccessController()
        application.delegate = controller
        withExtendedLifetime(lease) { application.run() }
    }
}
#endif
