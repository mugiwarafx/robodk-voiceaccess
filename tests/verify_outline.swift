import AppKit
import Foundation

private final class OutlineFixture: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var roots: [StationNode]
    var selectedIDs: [String] = []
    override init() {
        roots = [StationNode([
            "id": "station", "label": "Station. Example", "children": [
                ["id": "notes", "label": "Notes. Description"],
                ["id": "frame", "label": "Reference frame. Frame", "children": [
                    ["id": "target", "label": "Target. Target1"],
                ]],
                ["id": "program", "label": "Program. Main. 13 instructions", "children": (1...13).map {
                    ["id": "instruction:\($0)", "label": "\($0) of 13. Tube\($0)"]
                }],
                ["id": "symbol", "label": "Robot. ABB 120-3/0.6", "accessibility_label": "Robot. ABB 120 dash 3 slash 0.6"],
            ] as [[String: Any]],
        ])]
    }
    func outlineView(_ view: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? StationNode)?.children.count ?? roots.count }
    func outlineView(_ view: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? StationNode)?.children ?? roots)[index] }
    func outlineView(_ view: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! StationNode).children.isEmpty }
    func outlineView(_ view: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: (item as! StationNode).label)
        text.frame = NSRect(x: 3, y: 0, width: 450, height: 24)
        cell.addSubview(text)
        cell.textField = text
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let view = notification.object as? StationOutlineView, let node = view.item(atRow: view.selectedRow) as? StationNode else { return }
        selectedIDs.append(node.id)
        view.notifyAccessibilitySelection()
    }
}

@main
@available(macOS, deprecated: 10.10, message: "Checks both modern accessibility and AppKit's compatibility entry points")
struct VerifyOutline {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 180), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        let source = OutlineFixture()
        let outline = StationOutlineView()
        let column = NSTableColumn(identifier: .init("items"))
        column.title = "Items and instructions"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 28
        outline.dataSource = source
        outline.delegate = source
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.hasVerticalScroller = true
        scroll.documentView = outline
        window.contentView!.addSubview(scroll)
        outline.reloadData()
        outline.expandItem(source.roots[0], expandChildren: true)
        window.contentView!.layoutSubtreeIfNeeded()

        let rows = outline.accessibilityRows()!
        precondition(rows.count == 19 && outline.numberOfRows == 19)
        precondition(rows.allSatisfy { $0 is StationAccessibilityRow })
        let station = rows[0] as! StationAccessibilityRow
        let notes = rows[1] as! StationAccessibilityRow
        precondition(station.accessibilityRole() == .row && notes.accessibilityLabel() == "Notes. Description")
        precondition(notes.isAccessibilityEnabled())
        precondition(notes.accessibilitySubrole() == .outlineRow)
        precondition(notes.isAccessibilitySelectorAllowed(NSSelectorFromString("accessibilityPerformShowMenu")))
        precondition(notes.isAccessibilitySelectorAllowed(NSSelectorFromString("setAccessibilityFocused:")))
        precondition(notes.accessibilityParent() as? StationOutlineView === outline)
        precondition(outline.accessibilityChildrenInNavigationOrder()?.count == rows.count)
        precondition(outline.accessibilityColumns()?.count == 1)
        let cell = notes.accessibilityChildren()!.first as! NSAccessibilityElement
        let text = cell.accessibilityChildren()!.first as! NSAccessibilityElement
        precondition(cell.accessibilityRole() == .cell && text.accessibilityRole() == .staticText)
        precondition(cell.isAccessibilityEnabled() && text.isAccessibilityEnabled())
        precondition(text.isAccessibilitySelectorAllowed(NSSelectorFromString("accessibilityPerformShowMenu")))
        precondition(text.accessibilityValue() as? String == "Notes. Description")
        precondition(cell.accessibilityRowIndexRange() == NSRange(location: 1, length: 1))

        // Clients may use either the modern row getter or the legacy attribute
        // bridge. Both must return the same labelled, selectable row identities.
        let legacy = outline.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: "AXRows")!.takeUnretainedValue() as! [Any]
        precondition(legacy.count == rows.count)
        precondition(legacy[1] as? StationAccessibilityRow === notes)
        precondition(outline.accessibilityArrayAttributeCount(.rows) == rows.count)
        let sliced = outline.accessibilityArrayAttributeValues(.rows, index: 1, maxCount: 1)
        precondition(sliced.count == 1 && sliced[0] as? StationAccessibilityRow === notes)
        precondition(outline.accessibilityArrayAttributeValues(.rows, index: 999, maxCount: Int.max).isEmpty)
        precondition(outline.accessibilityIndex(ofChild: notes) == 1)

        outline.setAccessibilitySelectedRows([notes])
        precondition(outline.selectedRow == 1 && window.firstResponder === outline)
        precondition(source.selectedIDs.last == "notes")
        precondition(notes.isAccessibilitySelected() && notes.isAccessibilityFocused())
        precondition(outline.accessibilitySelectedRows()!.first as? StationAccessibilityRow === notes)
        precondition(outline.accessibilitySelectedCells()!.first as? NSAccessibilityElement === cell)
        precondition(outline.accessibilityFocusedUIElement as? NSAccessibilityElement === cell)
        let point = NSPoint(x: notes.accessibilityFrame().midX, y: notes.accessibilityFrame().midY)
        precondition(outline.accessibilityHitTest(point) as? NSAccessibilityElement === cell)
        outline.accessibilitySetValue([station], forAttribute: .selectedRows)
        precondition(outline.selectedRow == 0)
        outline.accessibilitySetValue([notes], forAttribute: .selectedRows)
        precondition(outline.selectedRow == 1)

        func arrow(_ character: String, _ keyCode: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!
            window.sendEvent(event)
        }
        arrow("\u{f701}", 125)
        precondition(outline.selectedRow == 2 && source.selectedIDs.last == "frame")
        arrow("\u{f700}", 126)
        precondition(outline.selectedRow == 1)

        let frame = outline.accessibleRow(at: 2)!
        let target = outline.accessibleRow(at: 3)!
        precondition(target.accessibilityDisclosureLevel() == 2)
        precondition(target.accessibilityDisclosedByRow() as? StationAccessibilityRow === frame)
        frame.setAccessibilityDisclosed(false)
        precondition(outline.numberOfRows == 18 && target.index == -1 && !target.isAccessibilityElement())
        precondition(outline.selectedRow == frame.index && frame.index == 2)
        precondition(frame.isAccessibilityFocused() && source.selectedIDs.last == "frame")
        arrow("\u{f701}", 125)
        precondition((outline.item(atRow: outline.selectedRow) as? StationNode)?.id == "program")
        frame.setAccessibilityDisclosed(true)
        precondition(outline.numberOfRows == 19 && outline.accessibleRow(at: 3) === target)
        precondition(outline.selectedRow == frame.index && frame.isAccessibilityFocused())
        // The native disclosure path also retains the parent when its selected
        // descendant disappears, and keeps an unrelated selection by identity.
        _ = target.accessibilityPerformPress()
        outline.collapseItem(frame.node)
        precondition(outline.selectedRow == frame.index)
        outline.expandItem(frame.node)
        _ = outline.selectAccessibleRow(18)
        outline.collapseItem(frame.node)
        precondition((outline.item(atRow: outline.selectedRow) as? StationNode)?.id == "symbol")
        outline.expandItem(frame.node)

        let last = outline.accessibleRow(at: 18)!
        precondition(last.accessibilityPerformPress())
        precondition(outline.selectedRow == 18 && source.selectedIDs.last == "symbol")
        precondition(outline.rect(ofRow: 18).intersects(outline.visibleRect))
        precondition(last.accessibilityFrame().height == outline.rowHeight)
        let spoken = (last.cell.accessibilityChildren()!.first as! NSAccessibilityElement).accessibilityValue() as! String
        precondition(spoken.contains("dash") && spoken.contains("slash"))
        precondition((outline.item(atRow: 18) as! StationNode).label == "Robot. ABB 120-3/0.6")
        cell.setAccessibilityFocused(true)
        precondition(outline.selectedRow == 1)
        outline.setAccessibilityFocused(true)
        precondition(window.firstResponder === outline)

        // A real reload/filter removes stale row identities instead of leaving
        // VoiceOver pointing at a row whose index now belongs to another item.
        source.roots = [StationNode(["id": "new", "label": "Program. Filtered"])]
        outline.reloadData()
        precondition(!notes.isAccessibilityElement() && !notes.accessibilityPerformPress())
        precondition(outline.accessibilityRows()!.count == 1)
        outline.focusSelection()
        precondition(outline.selectedRow == 0)
        let report: [String: Any] = [
            "public_and_legacy_row_hierarchy_checked": true,
            "attribute_array_slices_and_child_indexes_checked": true,
            "focus_hit_testing_and_attribute_selection_checked": true,
            "labelled_rows_and_cells_checked": true,
            "ax_selection_updates_model_and_keyboard_focus": true,
            "plain_arrow_events_checked": true,
            "expand_collapse_and_parent_levels_checked": true,
            "collapse_preserves_parent_focus_and_next_navigation": true,
            "native_collapse_preserves_selection_identity": true,
            "offscreen_selection_scrolls_into_view": true,
            "row_identity_survives_expand_and_scroll": true,
            "stale_rows_invalid_after_reload": true,
            "spoken_symbols_preserve_visible_names": true,
            "native_row_count": rows.count,
            "manual_voiceover_validation_required": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if CommandLine.arguments.count > 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
        print(String(data: data, encoding: .utf8)!)
    }
}
