#!/usr/bin/env swift

import Cocoa

// -- Configuration (override via environment variables) --
let sitIntervalSeconds = TimeInterval(ProcessInfo.processInfo.environment["STAND_INTERVAL"].flatMap(Double.init) ?? 3000) // 50 min
let standDurationSeconds = TimeInterval(ProcessInfo.processInfo.environment["STAND_DURATION"].flatMap(Double.init) ?? 600) // 10 min
let trainingSetEveryNthTransition = ProcessInfo.processInfo.environment["STAND_TRAINING_EVERY"].flatMap { Int($0) } ?? 3
let skipPhrase = "skip"

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

struct RehabExercise {
    let exerciseName: String
    let overlayHeadline: String
    let formCue: String
    let completionPhrase: String
}

let microExerciseRotation: [RehabExercise] = [
    RehabExercise(
        exerciseName: "chin_tucks",
        overlayHeadline: "",
        formCue: "While standing: 10 chin tucks. Glide your head straight back into a double chin, hold each for 5 seconds.",
        completionPhrase: "chin tucks done"
    ),
    RehabExercise(
        exerciseName: "neck_shoulder_mobility",
        overlayHeadline: "",
        formCue: "While standing: 10 slow backward shoulder rolls, then turn to look over each shoulder 5 times per side.",
        completionPhrase: "mobility done"
    ),
]

let trainingExerciseRotation: [RehabExercise] = [
    RehabExercise(
        exerciseName: "band_pull_aparts",
        overlayHeadline: "TRAINING SET: BAND PULL-APARTS",
        formCue: "One hard set, 12-15 reps. Arms straight, pull the band apart, squeeze the shoulder blades together. The last 3 reps should be a fight. Too easy means shorten your grip.",
        completionPhrase: "pull aparts done"
    ),
    RehabExercise(
        exerciseName: "band_face_pulls",
        overlayHeadline: "TRAINING SET: FACE PULLS",
        formCue: "One hard set, 12-15 reps. Anchor or hold the band out front, pull toward your face with elbows high, finish with hands beside your ears.",
        completionPhrase: "face pulls done"
    ),
    RehabExercise(
        exerciseName: "wall_slides",
        overlayHeadline: "TRAINING SET: WALL SLIDES",
        formCue: "10 slow reps. Back flat against the wall, wrists and elbows pinned to it, slide your arms overhead and back down.",
        completionPhrase: "wall slides done"
    ),
    RehabExercise(
        exerciseName: "thoracic_extension",
        overlayHeadline: "TRAINING SET: THORACIC EXTENSION",
        formCue: "60 seconds. Arch your upper back over the top edge of your chair back, arms overhead, and breathe slowly.",
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

// -- Overlay stages --
enum OverlayInputEvaluationResult {
    case rejected
    case advanceToNextStage
    case completeOverlay(confirmationText: String)
}

struct OverlayStage {
    let headlineText: String
    let cueText: String
    let promptText: String
    let evaluateTypedInput: (String) -> OverlayInputEvaluationResult
}

// Borderless windows refuse key status by default -- override that
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// -- Overlay window that blocks everything --
class BlockingOverlayController: NSObject, NSTextFieldDelegate {
    var windows: [NSWindow] = []
    var textField: NSTextField?
    var headlineLabel: NSTextField?
    var cueLabel: NSTextField?
    var promptLabel: NSTextField?
    var shakeTimer: Timer?
    var focusTimer: Timer?
    var onDismiss: (() -> Void)?
    var stages: [OverlayStage] = []
    var currentStageIndex = 0
    var isCompleting = false
    var isShowing: Bool { !windows.isEmpty }

    func show(stages: [OverlayStage], onDismiss: @escaping () -> Void) {
        guard !stages.isEmpty else { return }
        self.stages = stages
        self.currentStageIndex = 0
        self.isCompleting = false
        self.onDismiss = onDismiss

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
            window.backgroundColor = NSColor(red: 0.1, green: 0.0, blue: 0.0, alpha: 0.97)
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false

            // Put the interactive content on the main screen; fall back to the first screen if main is gone
            let isInteractive = (screen == NSScreen.main) || (NSScreen.main == nil && screen == NSScreen.screens.first)
            if isInteractive {
                let contentView = NSView(frame: screen.frame)

                let headline = NSTextField(labelWithString: "")
                headline.font = NSFont.boldSystemFont(ofSize: 50)
                headline.textColor = NSColor.red
                headline.alignment = .center
                headline.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2 + 70,
                    width: screen.frame.width - 100,
                    height: 160
                )
                headline.maximumNumberOfLines = 2
                contentView.addSubview(headline)
                self.headlineLabel = headline

                let cue = NSTextField(labelWithString: "")
                cue.font = NSFont.systemFont(ofSize: 22)
                cue.textColor = NSColor(white: 0.85, alpha: 1.0)
                cue.alignment = .center
                cue.frame = NSRect(
                    x: screen.frame.width * 0.15,
                    y: screen.frame.height / 2 - 40,
                    width: screen.frame.width * 0.7,
                    height: 100
                )
                cue.maximumNumberOfLines = 4
                contentView.addSubview(cue)
                self.cueLabel = cue

                let prompt = NSTextField(labelWithString: "")
                prompt.font = NSFont.systemFont(ofSize: 20)
                prompt.textColor = NSColor(white: 0.55, alpha: 1.0)
                prompt.alignment = .center
                prompt.frame = NSRect(
                    x: 50,
                    y: screen.frame.height / 2 - 90,
                    width: screen.frame.width - 100,
                    height: 40
                )
                contentView.addSubview(prompt)
                self.promptLabel = prompt

                let input = NSTextField(frame: NSRect(
                    x: screen.frame.width / 2 - 200,
                    y: screen.frame.height / 2 - 160,
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

        renderCurrentStage()

        if let tf = textField, let mainWin = windows.first(where: { $0.contentView?.subviews.contains(tf) == true }) {
            mainWin.makeFirstResponder(tf)
        }

        shakeTimer?.invalidate()
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.shakeHeadline()
        }

        // Reclaim focus every second without re-selecting text if already focused
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, !self.windows.isEmpty, !self.isCompleting else {
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

    private func renderCurrentStage() {
        guard currentStageIndex < stages.count else { return }
        let stage = stages[currentStageIndex]
        headlineLabel?.stringValue = stage.headlineText
        cueLabel?.stringValue = stage.cueText
        promptLabel?.stringValue = stage.promptText
        textField?.stringValue = ""
    }

    @objc private func screensChanged() {
        guard isShowing, !isCompleting else { return }

        shakeTimer?.invalidate()
        focusTimer?.invalidate()
        shakeTimer = nil
        focusTimer = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        textField = nil
        headlineLabel = nil
        cueLabel = nil
        promptLabel = nil

        buildWindows()
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
                beginCompletion(confirmationText: "DONE")
            }
        case .completeOverlay(let confirmationText):
            beginCompletion(confirmationText: confirmationText)
        }
    }

    private func beginCompletion(confirmationText: String) {
        isCompleting = true
        shakeTimer?.invalidate()
        shakeTimer = nil
        headlineLabel?.stringValue = confirmationText
        headlineLabel?.textColor = NSColor.green
        cueLabel?.stringValue = ""
        promptLabel?.stringValue = ""
        textField?.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismiss()
        }
    }

    func shakeHeadline() {
        guard let label = headlineLabel else { return }
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
        headlineLabel = nil
        cueLabel = nil
        promptLabel = nil
        isCompleting = false
        onDismiss?()
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

    let overlay = BlockingOverlayController()
    var sitPhaseTimer: Timer?
    var standPhaseTimer: Timer?
    var statusItem: NSStatusItem?
    var currentPhase: Phase = .sitting
    var standTransitionCounter = 0

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
        switch currentPhase {
        case .sitting: phaseLabel = "Sit"
        case .overlayShowing: phaseLabel = "STAND!"
        case .standing: phaseLabel = "Standing"
        case .snoozed: phaseLabel = "Snoozed"
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

    func triggerStandOverlay(forceTrainingSet: Bool = false) {
        guard !overlay.isShowing else { return }
        standTransitionCounter += 1
        currentPhase = .overlayShowing
        refreshMenuBarTitle()

        let isTrainingTransition = forceTrainingSet || (standTransitionCounter % trainingSetEveryNthTransition == 0)
        var overlayStages: [OverlayStage] = []
        if isFridayPainCheckDue() {
            overlayStages.append(makePainRatingStage())
        }
        overlayStages.append(makeExerciseStage(isTrainingTransition: isTrainingTransition))

        NSApp.activate(ignoringOtherApps: true)
        overlay.show(stages: overlayStages) { [weak self] in
            self?.startStandPhase()
        }
    }

    func makeExerciseStage(isTrainingTransition: Bool) -> OverlayStage {
        let exercise: RehabExercise
        let exerciseKind: String
        let headlineText: String

        if isTrainingTransition {
            exercise = trainingExerciseRotation[countTrainingPromptsEverLogged() % trainingExerciseRotation.count]
            exerciseKind = "training"
            headlineText = exercise.overlayHeadline
        } else {
            exercise = microExerciseRotation[countMicroPromptsEverLogged() % microExerciseRotation.count]
            exerciseKind = "micro"
            headlineText = standMessages.randomElement() ?? standMessages[0]
        }

        var cueText = exercise.formCue
        if isTrainingTransition && isMondayProgressionNudgeDue() {
            cueText += "\n\nMonday check: if last week's sets felt easy, shorten your grip or add a band."
        }

        return OverlayStage(
            headlineText: headlineText,
            cueText: cueText,
            promptText: "Type \"\(exercise.completionPhrase)\" when done, or \"\(skipPhrase)\"",
            evaluateTypedInput: { [weak self] typedInput in
                if typedInput == exercise.completionPhrase.lowercased() {
                    RehabEventLog.append(["event": "set_completed", "exercise": exercise.exerciseName, "kind": exerciseKind])
                    self?.refreshMenuBarTitle()
                    if exerciseKind == "training" {
                        let stats = computeRehabDailyStats()
                        return .completeOverlay(confirmationText: "LOGGED. \(stats.trainingSetsCompletedToday) SETS TODAY. STREAK: \(stats.dayStreak) DAYS.")
                    }
                    return .completeOverlay(confirmationText: "LOGGED. NOW STAND.")
                }
                if typedInput == skipPhrase {
                    RehabEventLog.append(["event": "set_skipped", "exercise": exercise.exerciseName, "kind": exerciseKind])
                    self?.refreshMenuBarTitle()
                    return .completeOverlay(confirmationText: "SKIPPED. IT IS ON YOUR RECORD.")
                }
                return .rejected
            }
        )
    }

    func makePainRatingStage() -> OverlayStage {
        OverlayStage(
            headlineText: "FRIDAY PAIN CHECK",
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
        alert.informativeText = "Next stand in \(Int(sitIntervalSeconds / 60)) minutes. Training sets today: \(stats.trainingSetsCompletedToday). Streak: \(stats.dayStreak) days."
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
        guard !overlay.isShowing else { return }
        sitPhaseTimer?.invalidate()
        triggerStandOverlay()
    }

    @objc func triggerTrainingSetNow() {
        guard !overlay.isShowing else { return }
        sitPhaseTimer?.invalidate()
        triggerStandOverlay(forceTrainingSet: true)
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
