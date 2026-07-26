#!/usr/bin/env swift

import Cocoa

// -- Configuration (override via environment variables) --
let standInterval = TimeInterval(ProcessInfo.processInfo.environment["STAND_INTERVAL"].flatMap(Double.init) ?? 1500) // 25 min
let standDuration = TimeInterval(ProcessInfo.processInfo.environment["STAND_DURATION"].flatMap(Double.init) ?? 600)   // 10 min
let dismissPhrase = ProcessInfo.processInfo.environment["STAND_PHRASE"] ?? "i will stand"

let standMessages = [
    "STAND NOW TO PREVENT ETERNAL AGONY",
    "YOUR SPINE IS BEGGING YOU TO STAND",
    "STAND UP OR SUFFER THE CONSEQUENCES",
    "GET ON YOUR FEET. NOW.",
    "YOUR BODY WILL NOT FORGIVE YOU",
    "STANDING IS NOT OPTIONAL",
]

let sitMessages = [
    "OK YOU CAN SIT DOWN NOW",
    "REST EARNED. SIT.",
    "SITTING GRANTED. TIMER RESTARTED.",
]

// Borderless windows refuse key status by default — override that
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// -- Overlay window that blocks everything --
class BlockingOverlayController: NSObject, NSTextFieldDelegate {
    var windows: [NSWindow] = []
    var textField: NSTextField?
    var messageLabel: NSTextField?
    var instructionLabel: NSTextField?
    var shakeTimer: Timer?
    var focusTimer: Timer?
    var onDismiss: (() -> Void)?
    var currentMessage: String = ""
    var isShowing: Bool { !windows.isEmpty }

    func show(message: String, phrase: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.currentMessage = message

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        buildWindows(message: message, phrase: phrase)
    }

    private func buildWindows(message: String, phrase: String) {
        // Cover every currently-connected screen
        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.backgroundColor = NSColor(red: 0.1, green: 0.0, blue: 0.0, alpha: 0.97)
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false

            // Put the interactive content on the main screen; fall back to the first screen if main is gone
            let isInteractive = (screen == NSScreen.main) || (NSScreen.main == nil && screen == NSScreen.screens.first)
            if isInteractive {
                let contentView = NSView(frame: screen.frame)

                let label = NSTextField(labelWithString: message)
                label.font = NSFont.boldSystemFont(ofSize: 64)
                label.textColor = NSColor.red
                label.alignment = .center
                label.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2 + 40,
                    width: screen.frame.width - 100,
                    height: 200
                )
                label.maximumNumberOfLines = 3
                contentView.addSubview(label)
                self.messageLabel = label

                let instruction = NSTextField(labelWithString: "Type \"\(phrase)\" to dismiss")
                instruction.font = NSFont.systemFont(ofSize: 28)
                instruction.textColor = NSColor(white: 0.6, alpha: 1.0)
                instruction.alignment = .center
                instruction.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2 - 30,
                    width: screen.frame.width - 100,
                    height: 50
                )
                contentView.addSubview(instruction)
                self.instructionLabel = instruction

                let input = NSTextField(frame: NSRect(
                    x: screen.frame.width / 2 - 200,
                    y: screen.frame.height / 2 - 100,
                    width: 400,
                    height: 50
                ))
                input.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
                input.alignment = .center
                input.backgroundColor = NSColor(white: 0.15, alpha: 1.0)
                input.textColor = NSColor.white
                input.focusRingType = .none
                input.isBezeled = true
                input.bezelStyle = .roundedBezel
                input.delegate = self
                contentView.addSubview(input)
                self.textField = input

                window.contentView = contentView
            }

            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        if let tf = textField, let mainWin = windows.first(where: { $0.contentView?.subviews.contains(tf) == true }) {
            mainWin.makeFirstResponder(tf)
        }

        // Shake the text periodically for extra annoyance
        shakeTimer?.invalidate()
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.shakeMessage()
        }

        // Reclaim focus every second without re-selecting text if already focused
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, !self.windows.isEmpty else {
                timer.invalidate()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            for w in self.windows {
                w.orderFrontRegardless()
            }
            if let tf = self.textField,
               let mainWin = self.windows.first(where: { $0.contentView?.subviews.contains(tf) == true }) {
                if mainWin.firstResponder != tf.currentEditor() {
                    mainWin.makeFirstResponder(tf)
                }
            }
        }
    }

    @objc private func screensChanged() {
        guard isShowing else { return }

        // Tear down existing windows and rebuild for current screen layout
        shakeTimer?.invalidate()
        focusTimer?.invalidate()
        shakeTimer = nil
        focusTimer = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        textField = nil
        messageLabel = nil
        instructionLabel = nil

        buildWindows(message: currentMessage, phrase: dismissPhrase)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let tf = notification.object as? NSTextField else { return }
        let typed = tf.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        if typed == dismissPhrase.lowercased() {
            dismiss()
        }
    }

    func shakeMessage() {
        guard let label = messageLabel else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.5
        animation.values = [-20, 20, -15, 15, -10, 10, -5, 5, 0]
        label.layer?.add(animation, forKey: "shake")
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        shakeTimer?.invalidate()
        focusTimer?.invalidate()
        shakeTimer = nil
        focusTimer = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        textField = nil
        messageLabel = nil
        instructionLabel = nil
        onDismiss?()
    }
}

// -- Main app controller --
class StandApp: NSObject, NSApplicationDelegate {
    let overlay = BlockingOverlayController()
    var standTimer: Timer?
    var sitTimer: Timer?
    var statusItem: NSStatusItem?
    var pauseMenuItem: NSMenuItem?
    var isStanding = false
    var isPaused = false
    var pausedFireDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        scheduleStandReminder()
        printConfig()
    }

    func printConfig() {
        let standMin = Int(standInterval / 60)
        let sitMin = Int(standDuration / 60)
        print("Stand reminder active:")
        print("  Stand every: \(standMin) min")
        print("  Stand for:   \(sitMin) min")
        print("  Dismiss phrase: \"\(dismissPhrase)\"")
        print("  Env vars: STAND_INTERVAL (seconds), STAND_DURATION (seconds), STAND_PHRASE")
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Stand"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Trigger Stand Now", action: #selector(triggerStandNow), keyEquivalent: ""))

        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseItem)
        self.pauseMenuItem = pauseItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func scheduleStandReminder() {
        standTimer?.invalidate()
        isStanding = false
        isPaused = false
        pausedFireDate = nil
        pauseMenuItem?.title = "Pause"
        statusItem?.button?.title = "Sit"

        standTimer = Timer.scheduledTimer(withTimeInterval: standInterval, repeats: false) { [weak self] _ in
            self?.triggerStandOverlay()
        }
    }

    func triggerStandOverlay() {
        isStanding = true
        statusItem?.button?.title = "STAND!"

        let msg = standMessages.randomElement() ?? standMessages[0]
        NSApp.activate(ignoringOtherApps: true)
        overlay.show(message: msg, phrase: dismissPhrase) { [weak self] in
            self?.startStandingTimer()
        }
    }

    func startStandingTimer() {
        statusItem?.button?.title = "Standing..."
        sitTimer = Timer.scheduledTimer(withTimeInterval: standDuration, repeats: false) { [weak self] _ in
            self?.triggerSitOverlay()
        }
    }

    func triggerSitOverlay() {
        let msg = sitMessages.randomElement() ?? sitMessages[0]

        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = "Timer restarting. Next stand in \(Int(standInterval / 60)) minutes."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()

        scheduleStandReminder()
    }

    @objc func triggerStandNow() {
        standTimer?.invalidate()
        triggerStandOverlay()
    }

    @objc func togglePause() {
        if isPaused {
            // Resume: restart timer with remaining time, or full interval if unknown
            isPaused = false
            let remaining: TimeInterval
            if let fireDate = pausedFireDate {
                remaining = max(1, fireDate.timeIntervalSinceNow)
            } else {
                remaining = standInterval
            }
            pausedFireDate = nil
            standTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                self?.triggerStandOverlay()
            }
            pauseMenuItem?.title = "Pause"
            statusItem?.button?.title = "Sit"
        } else {
            guard !isStanding else { return } // can't pause during stand
            isPaused = true
            pausedFireDate = standTimer?.fireDate
            standTimer?.invalidate()
            standTimer = nil
            pauseMenuItem?.title = "Resume"
            statusItem?.button?.title = "Paused"
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// -- Entry point --
let app = NSApplication.shared
let delegate = StandApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
