import AppKit
import Foundation

private var dockController: VoiceAccessController?
private var dockView: NSView?

public typealias DockVisibilityCallback = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void

@_cdecl("va_dock_create")
public func createDock(_ configuration: UnsafePointer<CChar>, _ callback: DockVisibilityCallback?, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread, dockController == nil,
          let data = String(cString: configuration).data(using: .utf8),
          let options = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
    let controller = VoiceAccessController()
    let view = controller.createEmbedded(options)
    controller.embeddedVisibility = { visible in callback?(visible ? 1 : 0, context) }
    dockController = controller; dockView = view
    return Unmanaged.passUnretained(view).toOpaque()
}

@_cdecl("va_dock_attach")
public func attachDock() { dockController?.attachEmbedded() }

@_cdecl("va_dock_visible")
public func dockVisible(_ visible: Int32) { dockController?.embeddedDidChangeVisibility(visible != 0) }

@_cdecl("va_dock_command")
public func dockCommand(_ command: UnsafePointer<CChar>, _ payload: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    guard Thread.isMainThread, let controller = dockController else { return strdup("{}") }
    let name = String(cString: command)
    let data = String(cString: payload).data(using: .utf8) ?? Data()
    let options = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    if ["show", "hide", "read-selection", "silence"].contains(name) {
        controller.receiveCommand(name, items: options["items"] as? [String] ?? [])
    }
    let report = controller.embeddedReport(checkNavigation: name == "self-test", preview: options["preview"] as? String)
    let result = (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data("{}".utf8)
    return strdup(String(data: result, encoding: .utf8) ?? "{}")
}

@_cdecl("va_dock_destroy")
public func destroyDock() {
    dockController?.embeddedVisibility = nil
    dockController?.stopEmbedded()
    dockController = nil; dockView = nil
}
