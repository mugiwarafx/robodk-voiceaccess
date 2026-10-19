import Foundation

/// Automatic updates finish the current utterance and retain only the newest
/// pending update. Explicit reading commands may interrupt and clear the queue.
/// All state changes run on the main thread, including process completions.
final class LocalSpeech {
    enum AutomaticPriority: Int { case selection, execution }
    typealias ProcessFactory = (String, Int, String?) -> Process
    private let makeProcess: ProcessFactory
    private var process: Process?
    private var currentIsAutomatic = false
    private var pendingPriority: AutomaticPriority?
    private(set) var currentText: String?
    private(set) var pendingText: String?
    var voice: String?
    var rate = 175
    var onStarted: ((String) -> Void)?
    var onCompleted: ((String, Int32) -> Void)?

    init(makeProcess: ProcessFactory? = nil) {
        self.makeProcess = makeProcess ?? { text, rate, voice in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            var arguments = ["-r", String(rate)]
            if let voice = voice { arguments += ["-v", voice] }
            task.arguments = arguments + [text]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            return task
        }
    }

    var isSpeaking: Bool { process != nil }

    func stop() {
        pendingText = nil
        pendingPriority = nil
        currentText = nil
        currentIsAutomatic = false
        let previous = process
        process = nil
        previous?.terminationHandler = nil
        if let previous = previous, previous.isRunning { previous.terminate() }
    }

    func stopAutomatic() {
        pendingText = nil
        pendingPriority = nil
        if currentIsAutomatic { stop() }
    }

    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        start(text, automatic: false)
    }

    func narrate(_ text: String, priority: AutomaticPriority = .execution) {
        guard !text.isEmpty else { return }
        // Selection following must not replace a pending movement/final status.
        if let pendingPriority = pendingPriority, priority.rawValue < pendingPriority.rawValue { return }
        if text == currentText {
            pendingText = nil
            pendingPriority = nil
            return
        }
        if process != nil {
            pendingText = text
            pendingPriority = priority
        } else {
            start(text, automatic: true)
        }
    }

    private func start(_ text: String, automatic: Bool) {
        let task = makeProcess(text, rate, voice)
        process = task
        currentText = text
        currentIsAutomatic = automatic
        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                // A cancelled process may finish after a new manual read began.
                guard let self = self, self.process === finished else { return }
                self.process = nil
                self.currentText = nil
                self.currentIsAutomatic = false
                self.onCompleted?(text, finished.terminationStatus)
                if let next = self.pendingText {
                    self.pendingText = nil
                    self.pendingPriority = nil
                    self.start(next, automatic: true)
                }
            }
        }
        do {
            try task.run()
            onStarted?(text)
        } catch {
            task.terminationHandler = nil
            process = nil
            currentText = nil
            currentIsAutomatic = false
        }
    }
}
