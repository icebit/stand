#!/usr/bin/env swift

import Cocoa

// -- Configuration (override via environment variables) --
let sitIntervalSeconds = TimeInterval(ProcessInfo.processInfo.environment["STAND_INTERVAL"].flatMap(Double.init) ?? 3000) // 50 min
let standDurationSeconds = TimeInterval(ProcessInfo.processInfo.environment["STAND_DURATION"].flatMap(Double.init) ?? 600) // 10 min
let trainingSetEveryNthTransition = ProcessInfo.processInfo.environment["STAND_TRAINING_EVERY"].flatMap { Int($0) } ?? 3
let skipPhrase = "skip"

let fullscreenStandMessages = [
    "Time to stand",
    "Stand break",
    "On your feet for 10 minutes",
    "Stand up and reset",
]

let sitMessages = [
    "OK YOU CAN SIT DOWN NOW",
    "REST EARNED. SIT.",
    "SITTING GRANTED. TIMER RESTARTED.",
]

struct RehabExercise {
    let exerciseName: String
    let overlayHeadline: String
    let formCue: String
    let completionPhrase: String
}

let microExerciseRotation: [RehabExercise] = [
    RehabExercise(
        exerciseName: "chin_tucks",
        overlayHeadline: "Chin tucks",
        formCue: "10 reps: glide your head straight back into a double chin, hold each 5 seconds.",
        completionPhrase: "chin tucks done"
    ),
    RehabExercise(
        exerciseName: "neck_shoulder_mobility",
        overlayHeadline: "Mobility",
        formCue: "10 slow backward shoulder rolls, then look over each shoulder 5 times per side.",
        completionPhrase: "mobility done"
    ),
]

let trainingExerciseRotation: [RehabExercise] = [
    RehabExercise(
        exerciseName: "band_pull_aparts",
        overlayHeadline: "Training set: band pull-aparts",
        formCue: "One hard set, 12-15 reps. Arms straight, squeeze shoulder blades together. Last 3 reps should be a fight.",
        completionPhrase: "pull aparts done"
    ),
    RehabExercise(
        exerciseName: "band_face_pulls",
        overlayHeadline: "Training set: face pulls",
        formCue: "One hard set, 12-15 reps. Pull the band toward your face, elbows high, hands finish beside your ears.",
        completionPhrase: "face pulls done"
    ),
    RehabExercise(
        exerciseName: "wall_slides",
        overlayHeadline: "Training set: wall slides",
        formCue: "10 slow reps. Back flat against a wall, wrists and elbows pinned, slide arms overhead. Stairwell works.",
        completionPhrase: "wall slides done"
    ),
    RehabExercise(
        exerciseName: "thoracic_extension",
        overlayHeadline: "Training set: upper-back extension",
        formCue: "60 seconds. Arch your upper back over the top edge of your chair back, arms overhead, breathe slowly.",
        completionPhrase: "extension done"
    ),
]

let iso8601TimestampFormatter = ISO8601DateFormatter()

let dayStringFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

// -- Event log (jsonl, one event per line) --
enum RehabEventLog {
    static let logDirectoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".stand")
    static let logFileURL = logDirectoryURL.appendingPathComponent("log.jsonl")

    static func append(_ eventFields: [String: Any]) {
        var fields = eventFields
        let now = Date()
        fields["ts"] = iso8601TimestampFormatter.string(from: now)
        fields["day"] = dayStringFormatter.string(from: now)
        guard let lineData = try? JSONSerialization.data(withJSONObject: fields) else { return }
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        guard let fileHandle = try? FileHandle(forWritingTo: logFileURL) else { return }
        fileHandle.seekToEndOfFile()
        fileHandle.write(lineData)
        fileHandle.write(Data("\n".utf8))
        fileHandle.closeFile()
    }

    static func readAllEvents() -> [[String: Any]] {
        guard let rawContents = try? String(contentsOf: logFileURL, encoding: .utf8) else { return [] }
        return rawContents.split(separator: "\n").compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        }
    }
}

struct RehabDailyStats {
    let trainingSetsCompletedToday: Int
    let trainingSetsSkippedToday: Int
    let dayStreak: Int
}

func computeRehabDailyStats() -> RehabDailyStats {
    let allEvents = RehabEventLog.readAllEvents()
    let todayString = dayStringFormatter.string(from: Date())

    var trainingSetsCompletedPerDay: [String: Int] = [:]
    var daysWithAnyEvents = Set<String>()
    var trainingSetsSkippedToday = 0

    for event in allEvents {
        guard let dayString = event["day"] as? String else { continue }
        daysWithAnyEvents.insert(dayString)
        let eventType = event["event"] as? String
        let eventKind = event["kind"] as? String
        if eventType == "set_completed" && eventKind == "training" {
            trainingSetsCompletedPerDay[dayString, default: 0] += 1
        }
        if eventType == "set_skipped" && eventKind == "training" && dayString == todayString {
            trainingSetsSkippedToday += 1
        }
    }

    var dayStreak = 0
    for dayString in daysWithAnyEvents.sorted(by: >) {
        let setsCompleted = trainingSetsCompletedPerDay[dayString] ?? 0
        if dayString == todayString {
            if setsCompleted > 0 { dayStreak += 1 }
            continue
        }
        if setsCompleted > 0 { dayStreak += 1 } else { break }
    }

    return RehabDailyStats(
        trainingSetsCompletedToday: trainingSetsCompletedPerDay[todayString] ?? 0,
        trainingSetsSkippedToday: trainingSetsSkippedToday,
        dayStreak: dayStreak
    )
}

func countTrainingPromptsEverLogged() -> Int {
    RehabEventLog.readAllEvents().filter { event in
        let eventType = event["event"] as? String
        return (eventType == "set_completed" || eventType == "set_skipped")
            && (event["kind"] as? String) == "training"
    }.count
}

func countMicroPromptsEverLogged() -> Int {
    RehabEventLog.readAllEvents().filter { event in
        let eventType = event["event"] as? String
        return (eventType == "set_completed" || eventType == "set_skipped")
            && (event["kind"] as? String) == "micro"
    }.count
}

func hasPainCheckHappenedToday() -> Bool {
    let todayString = dayStringFormatter.string(from: Date())
    return RehabEventLog.readAllEvents().contains { event in
        let eventType = event["event"] as? String
        return (eventType == "pain_rating" || eventType == "pain_check_skipped")
            && (event["day"] as? String) == todayString
    }
}

func hasCompletedTrainingSetToday() -> Bool {
    let todayString = dayStringFormatter.string(from: Date())
    return RehabEventLog.readAllEvents().contains { event in
        (event["event"] as? String) == "set_completed"
            && (event["kind"] as? String) == "training"
            && (event["day"] as? String) == todayString
    }
}

func recentPainRatingLines(maxCount: Int) -> [String] {
    let painEvents = RehabEventLog.readAllEvents().filter { ($0["event"] as? String) == "pain_rating" }
    return painEvents.suffix(maxCount).compactMap { event in
        guard let dayString = event["day"] as? String, let score = event["score"] as? Int else { return nil }
        return "\(dayString): \(score)/10"
    }
}

// -- Fullscreen attention overlay: neutral look, dismissed instantly with esc or return --
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class DismissKeyCaptureView: NSView {
    var onDismissKey: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        // 53 = escape, 36 = return
        if event.keyCode == 53 || event.keyCode == 36 {
            onDismissKey?()
        }
    }
}

class FullscreenAttentionOverlayController: NSObject {
    var windows: [NSWindow] = []
    var focusTimer: Timer?
    var onDismiss: (() -> Void)?
    var currentMessage = ""
    var isShowing: Bool { !windows.isEmpty }

    func show(message: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.currentMessage = message

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        buildWindows()
    }

    private func buildWindows() {
        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 0.97)
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false

            let isInteractive = (screen == NSScreen.main) || (NSScreen.main == nil && screen == NSScreen.screens.first)
            if isInteractive {
                let captureView = DismissKeyCaptureView(frame: screen.frame)
                captureView.onDismissKey = { [weak self] in self?.dismiss() }

                let messageLabel = NSTextField(labelWithString: currentMessage)
                messageLabel.font = NSFont.systemFont(ofSize: 30, weight: .medium)
                messageLabel.textColor = NSColor(white: 0.9, alpha: 1.0)
                messageLabel.alignment = .center
                messageLabel.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2,
                    width: screen.frame.width - 100,
                    height: 50
                )
                captureView.addSubview(messageLabel)

                let hintLabel = NSTextField(labelWithString: "esc to dismiss - exercise appears in the corner")
                hintLabel.font = NSFont.systemFont(ofSize: 14)
                hintLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
                hintLabel.alignment = .center
                hintLabel.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2 - 50,
                    width: screen.frame.width - 100,
                    height: 30
                )
                captureView.addSubview(hintLabel)

                window.contentView = captureView
                window.makeFirstResponder(captureView)
            }

            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

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
            if let captureView = self.windows.compactMap({ $0.contentView as? DismissKeyCaptureView }).first,
               let win = captureView.window, win.firstResponder != captureView {
                win.makeFirstResponder(captureView)
            }
        }
    }

    @objc private func screensChanged() {
        guard isShowing else { return }
        teardownWindows()
        buildWindows()
    }

    private func teardownWindows() {
        focusTimer?.invalidate()
        focusTimer = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        teardownWindows()
        onDismiss?()
    }
}

// -- Corner panel: small, quiet, holds the exercise until completed or skipped --
enum PanelInputEvaluationResult {
    case rejected
    case advanceToNextStage
    case completePanel(confirmationText: String)
}

struct PanelStage {
    let headlineText: String
    let cueText: String
    let promptText: String
    let evaluateTypedInput: (String) -> PanelInputEvaluationResult
}

class CornerExercisePanelController: NSObject, NSTextFieldDelegate {
    var panel: NSPanel?
    var headlineLabel: NSTextField?
    var cueLabel: NSTextField?
    var promptLabel: NSTextField?
    var textField: NSTextField?
    var stages: [PanelStage] = []
    var currentStageIndex = 0
    var isCompleting = false
    var isShowing: Bool { panel != nil }

    func show(stages: [PanelStage]) {
        closeImmediately()
        guard !stages.isEmpty else { return }
        self.stages = stages
        self.currentStageIndex = 0
        self.isCompleting = false

        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 150
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.maxX - panelWidth - 16, y: screenFrame.minY + 16)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "stand"
        newPanel.level = .floating
        newPanel.isFloatingPanel = true
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = NSColor(white: 0.13, alpha: 1.0)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        let headline = NSTextField(labelWithString: "")
        headline.font = NSFont.boldSystemFont(ofSize: 13)
        headline.textColor = NSColor(white: 0.95, alpha: 1.0)
        headline.frame = NSRect(x: 14, y: panelHeight - 46, width: panelWidth - 28, height: 20)
        contentView.addSubview(headline)
        headlineLabel = headline

        let cue = NSTextField(wrappingLabelWithString: "")
        cue.font = NSFont.systemFont(ofSize: 11)
        cue.textColor = NSColor(white: 0.75, alpha: 1.0)
        cue.frame = NSRect(x: 14, y: panelHeight - 92, width: panelWidth - 28, height: 44)
        contentView.addSubview(cue)
        cueLabel = cue

        let prompt = NSTextField(labelWithString: "")
        prompt.font = NSFont.systemFont(ofSize: 10)
        prompt.textColor = NSColor(white: 0.5, alpha: 1.0)
        prompt.frame = NSRect(x: 14, y: panelHeight - 110, width: panelWidth - 28, height: 16)
        contentView.addSubview(prompt)
        promptLabel = prompt

        let input = NSTextField(frame: NSRect(x: 14, y: 10, width: panelWidth - 28, height: 26))
        input.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        input.backgroundColor = NSColor(white: 0.2, alpha: 1.0)
        input.textColor = NSColor.white
        input.focusRingType = .none
        input.isBezeled = true
        input.bezelStyle = .roundedBezel
        input.delegate = self
        contentView.addSubview(input)
        textField = input

        newPanel.contentView = contentView
        newPanel.orderFrontRegardless()
        panel = newPanel

        renderCurrentStage()
    }

    private func renderCurrentStage() {
        guard currentStageIndex < stages.count else { return }
        let stage = stages[currentStageIndex]
        headlineLabel?.stringValue = stage.headlineText
        cueLabel?.stringValue = stage.cueText
        promptLabel?.stringValue = stage.promptText
        textField?.stringValue = ""
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isCompleting, currentStageIndex < stages.count else { return }
        guard let tf = notification.object as? NSTextField else { return }
        let typedInput = tf.stringValue.lowercased().trimmingCharacters(in: .whitespaces)

        switch stages[currentStageIndex].evaluateTypedInput(typedInput) {
        case .rejected:
            break
        case .advanceToNextStage:
            if currentStageIndex + 1 < stages.count {
                currentStageIndex += 1
                renderCurrentStage()
            } else {
                beginCompletion(confirmationText: "Done")
            }
        case .completePanel(let confirmationText):
            beginCompletion(confirmationText: confirmationText)
        }
    }

    private func beginCompletion(confirmationText: String) {
        isCompleting = true
        headlineLabel?.stringValue = confirmationText
        headlineLabel?.textColor = NSColor.systemGreen
        cueLabel?.stringValue = ""
        promptLabel?.stringValue = ""
        textField?.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.closeImmediately()
        }
    }

    func closeImmediately() {
        panel?.orderOut(nil)
        panel = nil
        headlineLabel = nil
        cueLabel = nil
        promptLabel = nil
        textField = nil
        stages = []
        isCompleting = false
    }
}

// -- Main app controller --
class StandApp: NSObject, NSApplicationDelegate {
    enum Phase {
        case sitting
        case overlayShowing
        case standing
        case snoozed
    }

    let fullscreenOverlay = FullscreenAttentionOverlayController()
    let cornerPanel = CornerExercisePanelController()
    var sitPhaseTimer: Timer?
    var standPhaseTimer: Timer?
    var statusItem: NSStatusItem?
    var currentPhase: Phase = .sitting
    var standTransitionCounter = 0
    var pendingPanelExercise: RehabExercise?
    var pendingPanelExerciseKind: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        scheduleSitPhase()
        printConfig()
    }

    func printConfig() {
        print("Stand rehab reminder active:")
        print("  Sit for:      \(Int(sitIntervalSeconds / 60)) min")
        print("  Stand for:    \(Int(standDurationSeconds / 60)) min")
        print("  Training set: every \(trainingSetEveryNthTransition) transitions")
        print("  Log file:     \(RehabEventLog.logFileURL.path)")
        print("  Env vars: STAND_INTERVAL (seconds), STAND_DURATION (seconds), STAND_TRAINING_EVERY (count)")
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Trigger Stand Now", action: #selector(triggerStandNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Trigger Training Set Now", action: #selector(triggerTrainingSetNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Snooze 30 Minutes", action: #selector(snoozeThirtyMinutes), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Snooze 60 Minutes", action: #selector(snoozeSixtyMinutes), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Stats", action: #selector(showStats), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        refreshMenuBarTitle()
    }

    func refreshMenuBarTitle() {
        let stats = computeRehabDailyStats()
        let phaseLabel: String
        if cornerPanel.isShowing {
            phaseLabel = "Set pending"
        } else {
            switch currentPhase {
            case .sitting: phaseLabel = "Sit"
            case .overlayShowing: phaseLabel = "STAND!"
            case .standing: phaseLabel = "Standing"
            case .snoozed: phaseLabel = "Snoozed"
            }
        }
        statusItem?.button?.title = "\(phaseLabel) | \(stats.trainingSetsCompletedToday) sets | \(stats.dayStreak)d"
    }

    func scheduleSitPhase() {
        sitPhaseTimer?.invalidate()
        currentPhase = .sitting
        refreshMenuBarTitle()

        sitPhaseTimer = Timer.scheduledTimer(withTimeInterval: sitIntervalSeconds, repeats: false) { [weak self] _ in
            self?.triggerStandOverlay()
        }
    }

    func expirePendingPanelIfShowing() {
        guard cornerPanel.isShowing else { return }
        if let exercise = pendingPanelExercise, let kind = pendingPanelExerciseKind {
            RehabEventLog.append([
                "event": "set_skipped",
                "exercise": exercise.exerciseName,
                "kind": kind,
                "how": "expired",
            ])
        }
        pendingPanelExercise = nil
        pendingPanelExerciseKind = nil
        cornerPanel.closeImmediately()
    }

    func triggerStandOverlay(forceTrainingSet: Bool = false) {
        guard !fullscreenOverlay.isShowing else { return }
        expirePendingPanelIfShowing()
        standTransitionCounter += 1
        currentPhase = .overlayShowing
        refreshMenuBarTitle()

        let isTrainingTransition = forceTrainingSet || (standTransitionCounter % trainingSetEveryNthTransition == 0)

        NSApp.activate(ignoringOtherApps: true)
        let message = fullscreenStandMessages.randomElement() ?? fullscreenStandMessages[0]
        fullscreenOverlay.show(message: message) { [weak self] in
            self?.showExercisePanel(isTrainingTransition: isTrainingTransition)
            self?.startStandPhase()
        }
    }

    func showExercisePanel(isTrainingTransition: Bool) {
        var panelStages: [PanelStage] = []
        if isFridayPainCheckDue() {
            panelStages.append(makePainRatingStage())
        }
        panelStages.append(makeExerciseStage(isTrainingTransition: isTrainingTransition))
        cornerPanel.show(stages: panelStages)
        refreshMenuBarTitle()
    }

    func makeExerciseStage(isTrainingTransition: Bool) -> PanelStage {
        let exercise: RehabExercise
        let exerciseKind: String

        if isTrainingTransition {
            exercise = trainingExerciseRotation[countTrainingPromptsEverLogged() % trainingExerciseRotation.count]
            exerciseKind = "training"
        } else {
            exercise = microExerciseRotation[countMicroPromptsEverLogged() % microExerciseRotation.count]
            exerciseKind = "micro"
        }

        pendingPanelExercise = exercise
        pendingPanelExerciseKind = exerciseKind

        var cueText = exercise.formCue
        if isTrainingTransition && isMondayProgressionNudgeDue() {
            cueText += " Monday: progress the band if last week felt easy."
        }

        return PanelStage(
            headlineText: exercise.overlayHeadline,
            cueText: cueText,
            promptText: "Type \"\(exercise.completionPhrase)\" when done, or \"\(skipPhrase)\"",
            evaluateTypedInput: { [weak self] typedInput in
                if typedInput == exercise.completionPhrase.lowercased() {
                    RehabEventLog.append(["event": "set_completed", "exercise": exercise.exerciseName, "kind": exerciseKind])
                    self?.pendingPanelExercise = nil
                    self?.pendingPanelExerciseKind = nil
                    self?.refreshMenuBarTitle()
                    if exerciseKind == "training" {
                        let stats = computeRehabDailyStats()
                        return .completePanel(confirmationText: "Logged. \(stats.trainingSetsCompletedToday) sets today, streak \(stats.dayStreak)d.")
                    }
                    return .completePanel(confirmationText: "Logged.")
                }
                if typedInput == skipPhrase {
                    RehabEventLog.append(["event": "set_skipped", "exercise": exercise.exerciseName, "kind": exerciseKind])
                    self?.pendingPanelExercise = nil
                    self?.pendingPanelExerciseKind = nil
                    self?.refreshMenuBarTitle()
                    return .completePanel(confirmationText: "Skipped and logged.")
                }
                return .rejected
            }
        )
    }

    func makePainRatingStage() -> PanelStage {
        PanelStage(
            headlineText: "Friday pain check",
            cueText: "Average upper back and neck pain this week.",
            promptText: "Type a number 0-10, or \"\(skipPhrase)\"",
            evaluateTypedInput: { typedInput in
                if typedInput == skipPhrase {
                    RehabEventLog.append(["event": "pain_check_skipped"])
                    return .advanceToNextStage
                }
                if let painScore = Int(typedInput), (0...10).contains(painScore) {
                    RehabEventLog.append(["event": "pain_rating", "score": painScore])
                    return .advanceToNextStage
                }
                return .rejected
            }
        )
    }

    func isFridayPainCheckDue() -> Bool {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now)
        let hour = Calendar.current.component(.hour, from: now)
        return weekday == 6 && hour >= 12 && !hasPainCheckHappenedToday()
    }

    func isMondayProgressionNudgeDue() -> Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 2 && !hasCompletedTrainingSetToday()
    }

    func startStandPhase() {
        currentPhase = .standing
        refreshMenuBarTitle()
        standPhaseTimer?.invalidate()
        standPhaseTimer = Timer.scheduledTimer(withTimeInterval: standDurationSeconds, repeats: false) { [weak self] _ in
            self?.showSitAlert()
        }
    }

    func showSitAlert() {
        let stats = computeRehabDailyStats()
        let alert = NSAlert()
        alert.messageText = sitMessages.randomElement() ?? sitMessages[0]
        var infoText = "Sit back down: hips all the way back against the backrest, then lean. Next stand in \(Int(sitIntervalSeconds / 60)) minutes. Training sets today: \(stats.trainingSetsCompletedToday). Streak: \(stats.dayStreak) days."
        if cornerPanel.isShowing {
            infoText += " Your exercise is still pending in the corner panel."
        }
        alert.informativeText = infoText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()

        scheduleSitPhase()
    }

    @objc func showStats() {
        let stats = computeRehabDailyStats()
        let painLines = recentPainRatingLines(maxCount: 6)
        let painSummary = painLines.isEmpty ? "none yet" : painLines.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Rehab Stats"
        alert.informativeText = """
        Training sets today: \(stats.trainingSetsCompletedToday)
        Skipped today: \(stats.trainingSetsSkippedToday)
        Day streak: \(stats.dayStreak)

        Recent Friday pain ratings:
        \(painSummary)

        Log: \(RehabEventLog.logFileURL.path)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func triggerStandNow() {
        guard !fullscreenOverlay.isShowing else { return }
        sitPhaseTimer?.invalidate()
        triggerStandOverlay()
    }

    @objc func triggerTrainingSetNow() {
        guard !fullscreenOverlay.isShowing else { return }
        expirePendingPanelIfShowing()
        showExercisePanel(isTrainingTransition: true)
    }

    @objc func snoozeThirtyMinutes() {
        snooze(forSeconds: 30 * 60)
    }

    @objc func snoozeSixtyMinutes() {
        snooze(forSeconds: 60 * 60)
    }

    func snooze(forSeconds snoozeSeconds: TimeInterval) {
        guard currentPhase == .sitting else { return }
        sitPhaseTimer?.invalidate()
        currentPhase = .snoozed
        refreshMenuBarTitle()
        sitPhaseTimer = Timer.scheduledTimer(withTimeInterval: snoozeSeconds, repeats: false) { [weak self] _ in
            self?.triggerStandOverlay()
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
