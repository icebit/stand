#!/usr/bin/env swift

import Cocoa
import AVFoundation

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

// -- Sound generation using system sounds and speech --
// Keep a strong reference so the synthesizer isn't deallocated mid-speech
var activeSynth: AVSpeechSynthesizer?

func speak(_ text: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        let synth = AVSpeechSynthesizer()
        activeSynth = synth
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synth.speak(utterance)
    }
}

func playAlarm() {
    NSSound.beep()
    speak("Stand up right now. This is not a drill.")
}

func playSitSound() {
    speak("You may sit down now. Good job.")
}

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
    var soundTimer: Timer?
    var onDismiss: (() -> Void)?
    var currentMessage: String = ""

    func show(message: String, phrase: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.currentMessage = message

        // Cover every screen with a blocking window
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

            if screen == NSScreen.main {
                let contentView = NSView(frame: screen.frame)

                // Main warning message
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

                // Instruction to dismiss
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

                // Text input field
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

        // Force focus on the text field
        if let tf = textField, let mainWin = windows.first(where: { $0.contentView?.subviews.contains(tf) == true }) {
            mainWin.makeFirstResponder(tf)
        }

        // Repeat alarm sound every 8 seconds
        playAlarm()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            playAlarm()
        }

        // Shake the text periodically for extra annoyance
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.shakeMessage()
        }

        // Reclaim focus every second, but only re-focus the text field
        // if it doesn't already have focus (to avoid re-selecting all text)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
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
        shakeTimer?.invalidate()
        soundTimer?.invalidate()
        shakeTimer = nil
        soundTimer = nil
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
    var isStanding = false

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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func scheduleStandReminder() {
        standTimer?.invalidate()
        isStanding = false
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
        playSitSound()

        // Brief, non-blocking notification for sit
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
