import Foundation

@main
struct SpeechChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func until(_ condition: () -> Bool, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        require(condition(), "Speech check timed out")
    }

    static func settle(_ duration: TimeInterval = 0.2) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    static func sleeper() -> LocalSpeech {
        LocalSpeech(makeProcess: { _, _, _ in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sleep")
            task.arguments = ["0.12"]
            return task
        })
    }

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let audioDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        var checks: [String: Bool] = [:]

        // A burst must not terminate the phrase that is already speaking.
        let burst = sleeper()
        var started: [String] = []
        var completed: [(String, Int32)] = []
        burst.onStarted = { started.append($0) }
        burst.onCompleted = { completed.append(($0, $1)) }
        burst.narrate("Main. 1 of 13.")
        for step in 2...13 { burst.narrate("Main. \(step) of 13.") }
        require(burst.currentText == "Main. 1 of 13.", "An automatic update cut off the current phrase")
        require(burst.pendingText == "Main. 13 of 13.", "Old steps accumulated instead of coalescing")
        until { !burst.isSpeaking }
        require(started == ["Main. 1 of 13.", "Main. 13 of 13."], "A stale intermediate step was spoken")
        require(completed.count == 2 && completed.allSatisfy { $0.1 == 0 }, "A phrase failed to finish naturally")
        checks["automatic_updates_finish_current_phrase"] = true
        checks["only_latest_pending_step_is_spoken"] = true

        started = []; completed = []
        burst.narrate("Current step")
        burst.narrate("Outdated future step")
        burst.narrate("Current step")
        require(burst.pendingText == nil, "Returning to the spoken step retained a stale queued update")
        until { !burst.isSpeaking }
        require(started == ["Current step"], "A superseded step was spoken")
        checks["returning_to_current_step_discards_stale_pending_update"] = true

        started = []; completed = []
        burst.speak("Explicit details")
        burst.narrate("Main. 13 of 13. Execution finished or stopped.")
        burst.narrate("RoboDK selection details", priority: .selection)
        require(burst.pendingText == "Main. 13 of 13. Execution finished or stopped.", "Selection following displaced the final execution notice")
        until { !burst.isSpeaking }
        require(started.count == 2 && started.last == "Main. 13 of 13. Execution finished or stopped.", "Final execution notice was lost")
        checks["selection_following_cannot_displace_pending_execution_notice"] = true

        // Automatic updates also wait for a full, explicit details request.
        started = []; completed = []
        burst.speak("Read the selected item's complete details.")
        for step in 1...50 { burst.narrate("Automatic update \(step)") }
        require(burst.currentText == "Read the selected item's complete details.", "Narration interrupted a manual read")
        until { !burst.isSpeaking }
        require(started == ["Read the selected item's complete details.", "Automatic update 50"], "Manual priority or bounded queue failed")
        require(completed.allSatisfy { $0.1 == 0 }, "Manual reading was interrupted")
        checks["manual_reads_are_not_interrupted_by_narration"] = true

        // A termination callback queued before an explicit read must not
        // restart the old pending narration after the read replaces it.
        started = []; completed = []
        burst.narrate("Old narration")
        burst.narrate("Stale queued narration")
        Thread.sleep(forTimeInterval: 0.2)
        burst.speak("New explicit read")
        burst.narrate("New current step")
        until { !burst.isSpeaking }
        require(started == ["Old narration", "New explicit read", "New current step"], "A late callback resumed stale narration")
        checks["late_cancelled_callbacks_cannot_resume_old_queue"] = true

        // Silence discards the queue; disabling narration leaves manual speech.
        started = []; completed = []
        burst.narrate("Speaking now")
        burst.narrate("Must be cleared")
        burst.stop()
        settle()
        require(!burst.isSpeaking && burst.pendingText == nil && started == ["Speaking now"], "Silence resumed queued speech")
        checks["silence_clears_pending_speech"] = true
        burst.speak("Manual reading continues")
        burst.narrate("Discard automatic update")
        burst.stopAutomatic()
        require(burst.currentText == "Manual reading continues" && burst.pendingText == nil, "Disabling narration stopped manual reading")
        until { !burst.isSpeaking }
        checks["disabling_narration_preserves_manual_read"] = true

        // Exercise the production say process with complete audio files, at
        // the maximum supported rate of 350 words per minute.
        var audioFiles: [String] = []
        var realStarted: [String] = []
        var realCompleted: [[String: Any]] = []
        let real = LocalSpeech(makeProcess: { text, rate, voice in
            let path = audioDirectory.appendingPathComponent("voiceaccess-queue-\(audioFiles.count + 1).aiff")
            audioFiles.append(path.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            task.arguments = ["-v", voice ?? "Samantha", "-r", String(rate), "-o", path.path, text]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            return task
        })
        real.voice = "Samantha"
        real.rate = 350
        real.onStarted = { realStarted.append($0) }
        real.onCompleted = { realCompleted.append(["text": $0, "exit_status": $1]) }
        real.narrate("Main. 1 of 13. Joint move to the starting position.")
        for step in 2...12 { real.narrate("Main. \(step) of 13. Moving to the next target.") }
        real.narrate("Main. 13 of 13. Execution finished or stopped.")
        until({ !real.isSpeaking }, timeout: 20)
        require(realStarted.count == 2 && realCompleted.count == 2, "Production speech did not finish both phrases")
        require(realCompleted.allSatisfy { $0["exit_status"] as? Int32 == 0 }, "The production speech process was interrupted")
        for path in audioFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            require((attributes[.size] as? NSNumber)?.intValue ?? 0 > 10000, "An audio phrase is missing or truncated")
        }
        checks["production_say_finishes_at_350_words_per_minute"] = true
        let report: [String: Any] = [
            "checks": checks, "all_checks_passed": checks.values.allSatisfy { $0 },
            "speech_rate": 350, "queue_capacity": 1,
            "production_started": realStarted, "production_completed": realCompleted,
            "audio_files": audioFiles,
            "manual_listening_validation_required": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output)
        print("SPEECH_CHECKS_PASSED")
    }
}
