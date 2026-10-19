import Foundation
import Darwin

enum SpeechOutputMode: String {
    case automatic, voiceOver, ownVoice

    func usesOwnVoice(voiceOverRunning: Bool) -> Bool {
        if voiceOverRunning { return false }
        switch self {
        case .automatic: return !voiceOverRunning
        case .voiceOver: return false
        case .ownVoice: return true
        }
    }
}

/// The listener may not be ready when two RoboDK actions start together.
/// Keep one lease per RoboDK port for the full lifetime of the reader.
final class ReaderInstanceLease {
    private let descriptor: Int32
    init?(port: String, directory: URL? = nil) throws {
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/RoboDKVoiceAccess")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safePort = port.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safePort.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let path = folder.appendingPathComponent("reader-\(safePort).lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            Darwin.close(fd)
            if failure == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

final class SimulationAdmission {
    private(set) var pending = false
    private var lastStart = -Double.infinity
    func begin(running: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard !pending, !running, now - lastStart >= 0.75 else { return false }
        pending = true
        lastStart = now
        return true
    }
    func completed() { pending = false }
}

/// Commands from RoboDK's menu/context actions go to the existing panel for
/// that API port. Only these three reading/presentation commands are accepted.
final class IntegrationChannel {
    static let requestName = Notification.Name("com.robodk.voiceaccess.request")
    static let replyName = Notification.Name("com.robodk.voiceaccess.reply")
    private var observer: NSObjectProtocol?
    private var lastCommand = ""
    private var lastItems: [String] = []
    private var lastDelivery = Date.distantPast

    init(port: String, handler: @escaping (String, [String]) -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.requestName, object: "rdk:\(port)", queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let identifier = note.userInfo?["id"] as? String,
                  let command = note.userInfo?["command"] as? String,
                  ["show", "hide", "read-selection", "silence"].contains(command) else { return }
            let ids = (note.userInfo?["items"] as? [String] ?? []).filter {
                !$0.isEmpty && $0.allSatisfy(\.isNumber)
            }
            let now = Date()
            let duplicate = command == self.lastCommand && ids == self.lastItems && now.timeIntervalSince(self.lastDelivery) < 0.6
            if !duplicate {
                self.lastCommand = command; self.lastItems = ids; self.lastDelivery = now
                handler(command, ids)
            }
            DistributedNotificationCenter.default().postNotificationName(
                Self.replyName, object: identifier, userInfo: nil, deliverImmediately: true
            )
        }
    }

    deinit {
        if let observer = observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    static func request(command: String, port: String, items: [String] = [], timeout: TimeInterval = 1.5) -> Bool {
        guard ["show", "hide", "read-selection", "silence"].contains(command) else { return false }
        let identifier = UUID().uuidString
        var acknowledged = false
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: replyName, object: identifier, queue: .main) { _ in acknowledged = true }
        defer { center.removeObserver(token) }
        center.postNotificationName(requestName, object: "rdk:\(port)", userInfo: [
            "id": identifier, "command": command, "items": items,
        ], deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        while !acknowledged && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return acknowledged
    }
}
