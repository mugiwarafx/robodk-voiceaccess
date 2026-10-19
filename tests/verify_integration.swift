import Foundation

@main
struct IntegrationChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func main() throws {
        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--lease" {
            let lease = try ReaderInstanceLease(port: CommandLine.arguments[2], directory: URL(fileURLWithPath: CommandLine.arguments[3]))
            withExtendedLifetime(lease) { exit(lease == nil ? 75 : 0) }
        }
        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--sender" {
            let accepted = IntegrationChannel.request(command: CommandLine.arguments[2], port: CommandLine.arguments[3], items: ["123", "456"])
            exit(accepted ? 0 : 69)
        }
        let reportPath = URL(fileURLWithPath: CommandLine.arguments[1])
        let port = "test-" + UUID().uuidString
        var received: [[String: Any]] = []
        let channel = IntegrationChannel(port: port) { command, items in
            received.append(["command": command, "items": items, "handler_pid": ProcessInfo.processInfo.processIdentifier])
        }
        for command in ["show", "read-selection", "silence", "hide", "show"] {
            let sender = Process()
            sender.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            sender.arguments = ["--sender", command, port]
            try sender.run()
            let deadline = Date().addingTimeInterval(5)
            while sender.isRunning && Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            require(!sender.isRunning && sender.terminationStatus == 0, "The existing panel did not acknowledge a command")
        }
        require(IntegrationChannel.request(command: "show", port: port, items: ["123", "456"]), "Repeated command was not acknowledged")
        withExtendedLifetime(channel) {}
        require(received.count == 5, "A command was lost or duplicated")
        require(Set(received.compactMap { $0["handler_pid"] as? Int32 }).count == 1, "Commands did not reuse one companion")
        require(received[1]["items"] as? [String] == ["123", "456"], "Captured RoboDK selection was not preserved")
        require(!IntegrationChannel.request(command: "show", port: "missing-" + port, timeout: 0.1), "A different RoboDK session received the request")
        require(!IntegrationChannel.request(command: "simulate", port: port, timeout: 0.1), "An unsupported command was accepted")

        let modes: [(SpeechOutputMode, Bool, Bool)] = [
            (.automatic, false, true), (.automatic, true, false),
            (.voiceOver, false, false), (.voiceOver, true, false),
            (.ownVoice, false, true), (.ownVoice, true, false),
        ]
        for (mode, voiceOver, own) in modes {
            require(mode.usesOwnVoice(voiceOverRunning: voiceOver) == own, "VoiceOver output routing is incorrect")
        }
        let leaseFolder = FileManager.default.temporaryDirectory.appendingPathComponent("voiceaccess-lease-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: leaseFolder) }
        var lease = try ReaderInstanceLease(port: port, directory: leaseFolder)
        require(lease != nil, "First reader could not acquire its lease")
        func acquireInChild(_ requestedPort: String) throws -> Int32 {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--lease", requestedPort, leaseFolder.path]
            try child.run()
            child.waitUntilExit()
            return child.terminationStatus
        }
        let samePort = try acquireInChild(port)
        let otherPort = try acquireInChild(port + "-other")
        require(samePort == 75, "A second reader acquired the same RoboDK port")
        require(otherPort == 0, "A different RoboDK port was incorrectly locked")
        withExtendedLifetime(lease) {}
        lease = nil
        let reopened = try acquireInChild(port)
        require(reopened == 0, "Closing the reader did not release its lease")
        let admission = SimulationAdmission()
        require(admission.begin(running: false, now: 10), "First simulation request was rejected")
        require(!admission.begin(running: false, now: 10.1), "An in-flight simulation request was duplicated")
        admission.completed()
        require(!admission.begin(running: false, now: 10.2), "Double activation bypassed the cooldown")
        require(!admission.begin(running: true, now: 12), "A running simulation was started again")
        require(admission.begin(running: false, now: 13), "A later intentional run was rejected")
        let report: [String: Any] = [
            "all_checks_passed": true,
            "cross_process_acknowledgement": true,
            "same_companion_reused": true,
            "duplicate_read_command_coalesced": true,
            "cross_process_single_reader_lease_checked": true,
            "simulation_pending_running_and_double_activation_guards_checked": true,
            "captured_selection_preserved": true,
            "separate_robodk_ports_isolated": true,
            "non_reading_remote_commands_rejected": true,
            "voiceover_output_matrix_checked": true,
            "voiceover_disables_even_explicit_own_voice": true,
            "system_voiceover_setting_changed": false,
            "received_commands": received,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportPath)
        print("INTEGRATION_CHECKS_PASSED")
    }
}
