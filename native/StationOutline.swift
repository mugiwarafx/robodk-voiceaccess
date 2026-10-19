import AppKit

final class EmbeddedStationDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class EmbeddedStationView: NSView {
    var keyEquivalent: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Scope our shortcuts to this panel; RoboDK keeps its own menu and
        // shortcuts when focus is elsewhere in the host application.
        if let focused = window?.firstResponder as? NSView,
           focused === self || focused.isDescendant(of: self),
           keyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// Draw a solid highlight in the foreign Qt window. AppKit's vibrant default
// selection background can disappear against the host's backing view.
final class EmbeddedStationRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

final class VoiceAccessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class StationNode: NSObject {
    let id: String
    let name: String
    let label: String
    let accessibilityLabel: String
    let type: Int
    let children: [StationNode]
    init(_ object: [String: Any]) {
        id = object["id"] as? String ?? ""
        name = object["name"] as? String ?? ""
        label = object["label"] as? String ?? name
        accessibilityLabel = object["accessibility_label"] as? String ?? label
        type = object["type"] as? Int ?? 0
        children = (object["children"] as? [[String: Any]] ?? []).map(StationNode.init)
    }
}

// Keep accessibility identities tied to station items, independently of AppKit's
// recycled view cells. All rows, including rows outside the viewport, can be
// selected by accessibility clients without creating their visual views first.
final class StationOutlineView: NSOutlineView {
    var trace: ((String) -> Void)?
    private var rowElements: [String: StationAccessibilityRow] = [:]
    private lazy var columnElement = StationAccessibilityColumn(outline: self)

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard selectAccessibleRow(index) else { return nil }
        return menu
    }
    @discardableResult func showContextMenu(at index: Int) -> Bool {
        guard let menu = menu, selectAccessibleRow(index) else { return false }
        let rect = rect(ofRow: index)
        return menu.popUp(positioning: nil, at: NSPoint(x: visibleRect.minX + 30, y: rect.maxY), in: self)
    }
    override func accessibilityPerformShowMenu() -> Bool { showContextMenu(at: selectedRow) }

    override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        // AppKit can clear or move selection while removing descendant rows.
        // Restore by item identity, never by the row index that just changed.
        let selected = selectedRow >= 0 ? self.item(atRow: selectedRow) : nil
        super.collapseItem(item, collapseChildren: collapseChildren)
        if let selected = selected {
            let preserved = row(forItem: selected)
            let target = preserved >= 0 ? preserved : row(forItem: item)
            if target >= 0 {
                selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
                scrollRowToVisible(target)
            }
        }
    }

    override func reloadData() {
        for row in rowElements.values { NSAccessibility.post(element: row, notification: .uiElementDestroyed) }
        rowElements.removeAll()
        super.reloadData()
    }

    func accessibleRow(at index: Int) -> StationAccessibilityRow? {
        guard index >= 0, index < numberOfRows, let node = item(atRow: index) as? StationNode else { return nil }
        if let row = rowElements[node.id], row.node === node { return row }
        let row = StationAccessibilityRow(outline: self, node: node)
        rowElements[node.id] = row
        return row
    }

    private var allAccessibleRows: [StationAccessibilityRow] { (0..<numberOfRows).compactMap(accessibleRow) }
    override func accessibilityRows() -> [NSAccessibilityRow]? { trace?("ax.rows"); return allAccessibleRows }
    override func accessibilityVisibleRows() -> [NSAccessibilityRow]? {
        let range = rows(in: visibleRect)
        guard range.location != NSNotFound else { return [] }
        return (range.location..<min(numberOfRows, NSMaxRange(range))).compactMap(accessibleRow)
    }
    override func accessibilityChildren() -> [Any]? { allAccessibleRows + [columnElement] }
    override func accessibilityChildrenInNavigationOrder() -> [NSAccessibilityElementProtocol]? { allAccessibleRows }
    override func accessibilityColumns() -> [Any]? { [columnElement] }
    override func accessibilityVisibleColumns() -> [Any]? { [columnElement] }
    override func accessibilitySelectedRows() -> [NSAccessibilityRow]? { selectedRowIndexes.compactMap(accessibleRow) }
    override func accessibilitySelectedCells() -> [Any]? { selectedRowIndexes.compactMap { accessibleRow(at: $0)?.cell } }
    override func setAccessibilitySelectedRows(_ rows: [NSAccessibilityRow]?) {
        guard let row = rows?.first as? StationAccessibilityRow, row.outline === self else { return }
        _ = selectAccessibleRow(row.index)
    }
    override func setAccessibilityFocused(_ focused: Bool) {
        trace?("ax.focus.\(focused)")
        guard focused else { return }
        focusSelection()
    }

    // NSOutlineView still implements the attribute bridge itself. Overriding
    // only the modern getters leaves that bridge vending different private
    // rows, so accessibility clients would see two incompatible hierarchies.
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        switch attribute {
        case .rows: return accessibilityRows()
        case .visibleRows: return accessibilityVisibleRows()
        case .selectedRows: return accessibilitySelectedRows()
        case .children: return accessibilityChildren()
        case NSAccessibility.Attribute(rawValue: "AXChildrenInNavigationOrder"): return accessibilityChildrenInNavigationOrder()
        case .columns: return accessibilityColumns()
        case .visibleColumns: return accessibilityVisibleColumns()
        case .selectedCells: return accessibilitySelectedCells()
        default: return super.accessibilityAttributeValue(attribute)
        }
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityIsAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
        if attribute == .selectedRows || attribute == .focused { return true }
        return super.accessibilityIsAttributeSettable(attribute)
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        if attribute == .selectedRows { setAccessibilitySelectedRows(value as? [NSAccessibilityRow]) }
        else if attribute == .focused { setAccessibilityFocused((value as? NSNumber)?.boolValue ?? false) }
        else { super.accessibilitySetValue(value, forAttribute: attribute) }
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override var accessibilityFocusedUIElement: Any? { accessibleRow(at: selectedRow)?.cell ?? self }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let window = window else { return self }
        let windowPoint = window.convertPoint(fromScreen: point)
        let index = row(at: convert(windowPoint, from: nil))
        return accessibleRow(at: index)?.cell ?? self
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityArrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int {
        if let values = accessibilityAttributeValue(attribute) as? [Any] { return values.count }
        return super.accessibilityArrayAttributeCount(attribute)
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityArrayAttributeValues(_ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int) -> [Any] {
        guard let values = accessibilityAttributeValue(attribute) as? [Any] else { return super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount) }
        let start = max(0, min(index, values.count))
        let count = max(0, min(maxCount, values.count - start))
        return Array(values[start..<(start + count)])
    }
    @available(macOS, deprecated: 10.10, message: "Compatibility bridge for NSOutlineView's attribute-based accessibility implementation")
    override func accessibilityIndex(ofChild child: Any) -> Int {
        if let row = child as? StationAccessibilityRow, row.outline === self, row.index >= 0 { return row.index }
        if child as? StationAccessibilityColumn === columnElement { return numberOfRows }
        return NSNotFound
    }

    func screenFrame(forRow index: Int) -> NSRect {
        guard index >= 0, index < numberOfRows, let window = window else { return .zero }
        return window.convertToScreen(convert(rect(ofRow: index), to: nil))
    }

    @discardableResult func selectAccessibleRow(_ index: Int) -> Bool {
        guard index >= 0, index < numberOfRows else { return false }
        claimKeyboardFocus()
        selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        scrollRowToVisible(index)
        return true
    }

    func focusSelection() {
        claimKeyboardFocus()
        if selectedRow < 0, numberOfRows > 0 { selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        if selectedRow >= 0 { scrollRowToVisible(selectedRow) }
        notifyAccessibilitySelection()
    }

    private func claimKeyboardFocus() {
        if let window = window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
        }
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        trace?("keyboard.focus.\(accepted)")
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if (123...126).contains(event.keyCode) { trace?("tree.key.\(event.keyCode)") }
        super.keyDown(with: event)
    }

    func notifyAccessibilitySelection() {
        NSAccessibility.post(element: self, notification: .selectedRowsChanged)
        if window?.isKeyWindow == true, window?.firstResponder === self, let row = accessibleRow(at: selectedRow) {
            NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
        }
    }
}

final class StationAccessibilityRow: NSAccessibilityElement, NSAccessibilityRow {
    weak var outline: StationOutlineView?
    let node: StationNode
    lazy var cell = StationAccessibilityCell(row: self)
    var index: Int { outline?.row(forItem: node) ?? -1 }

    init(outline: StationOutlineView, node: StationNode) {
        self.outline = outline
        self.node = node
        super.init()
    }
    override func isAccessibilityElement() -> Bool { index >= 0 }
    override func isAccessibilityEnabled() -> Bool { index >= 0 }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .outlineRow }
    override func accessibilityParent() -> Any? { outline }
    override func accessibilityWindow() -> Any? { outline?.window }
    override func accessibilityTopLevelUIElement() -> Any? { outline?.window }
    override func accessibilityFrame() -> NSRect { outline?.screenFrame(forRow: index) ?? .zero }
    override func accessibilityLabel() -> String? { node.accessibilityLabel }
    override func accessibilityIdentifier() -> String { "voiceaccess.row.\(node.id)" }
    override func accessibilityIndex() -> Int { index }
    override func accessibilityChildren() -> [Any]? { [cell] }
    override func accessibilityDisclosureLevel() -> Int { max(0, outline?.level(forItem: node) ?? 0) }
    override func isAccessibilitySelected() -> Bool { index >= 0 && outline?.selectedRow == index }
    override func setAccessibilitySelected(_ selected: Bool) { if selected { _ = outline?.selectAccessibleRow(index) } }
    override func isAccessibilityFocused() -> Bool { isAccessibilitySelected() && outline?.window?.firstResponder === outline }
    override func setAccessibilityFocused(_ focused: Bool) { if focused { _ = outline?.selectAccessibleRow(index) } }
    override func accessibilityPerformPress() -> Bool { outline?.selectAccessibleRow(index) ?? false }
    override func accessibilityPerformPick() -> Bool { accessibilityPerformPress() }
    override func accessibilityPerformShowMenu() -> Bool { outline?.showContextMenu(at: index) ?? false }
    override func isAccessibilityDisclosed() -> Bool { outline?.isItemExpanded(node) ?? false }
    override func setAccessibilityDisclosed(_ disclosed: Bool) {
        guard index >= 0, let outline = outline, outline.isExpandable(node) else { return }
        if disclosed { outline.expandItem(node) } else { outline.collapseItem(node) }
        NSAccessibility.post(element: self, notification: disclosed ? .rowExpanded : .rowCollapsed)
        // Keep VoiceOver on this stable row. A layoutChanged notification for
        // the entire tree can reset its cursor to the first row.
        _ = outline.selectAccessibleRow(outline.row(forItem: node))
        outline.notifyAccessibilitySelection()
    }
    override func accessibilityDisclosedByRow() -> Any? {
        guard let outline = outline, let parent = outline.parent(forItem: node) else { return nil }
        return outline.accessibleRow(at: outline.row(forItem: parent))
    }
    override func accessibilityDisclosedRows() -> Any? {
        guard isAccessibilityDisclosed(), let outline = outline else { return [] }
        return node.children.compactMap { outline.accessibleRow(at: outline.row(forItem: $0)) }
    }
}

final class StationAccessibilityCell: NSAccessibilityElement {
    weak var row: StationAccessibilityRow?
    private lazy var text = StationAccessibilityText(cell: self)
    init(row: StationAccessibilityRow) { self.row = row; super.init() }
    override func isAccessibilityElement() -> Bool { row?.isAccessibilityElement() ?? false }
    override func isAccessibilityEnabled() -> Bool { row?.isAccessibilityEnabled() ?? false }
    override func accessibilityRole() -> NSAccessibility.Role? { .cell }
    override func accessibilityParent() -> Any? { row }
    override func accessibilityWindow() -> Any? { row?.accessibilityWindow() }
    override func accessibilityTopLevelUIElement() -> Any? { row?.accessibilityWindow() }
    override func accessibilityFrame() -> NSRect { row?.accessibilityFrame() ?? .zero }
    override func accessibilityChildren() -> [Any]? { [text] }
    override func accessibilityRowIndexRange() -> NSRange { NSRange(location: max(0, row?.index ?? 0), length: 1) }
    override func accessibilityColumnIndexRange() -> NSRange { NSRange(location: 0, length: 1) }
    override func isAccessibilitySelected() -> Bool { row?.isAccessibilitySelected() ?? false }
    override func setAccessibilitySelected(_ selected: Bool) { row?.setAccessibilitySelected(selected) }
    override func isAccessibilityFocused() -> Bool { row?.isAccessibilityFocused() ?? false }
    override func setAccessibilityFocused(_ focused: Bool) { row?.setAccessibilityFocused(focused) }
    override func accessibilityPerformPress() -> Bool { row?.accessibilityPerformPress() ?? false }
    override func accessibilityPerformShowMenu() -> Bool { row?.accessibilityPerformShowMenu() ?? false }
}

private final class StationAccessibilityText: NSAccessibilityElement {
    weak var cell: StationAccessibilityCell?
    init(cell: StationAccessibilityCell) { self.cell = cell; super.init() }
    override func isAccessibilityElement() -> Bool { cell?.isAccessibilityElement() ?? false }
    override func isAccessibilityEnabled() -> Bool { cell?.isAccessibilityEnabled() ?? false }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityParent() -> Any? { cell }
    override func accessibilityWindow() -> Any? { cell?.accessibilityWindow() }
    override func accessibilityTopLevelUIElement() -> Any? { cell?.accessibilityWindow() }
    override func accessibilityFrame() -> NSRect { cell?.accessibilityFrame() ?? .zero }
    override func accessibilityValue() -> Any? { cell?.row?.node.accessibilityLabel }
    override func accessibilityLabel() -> String? { cell?.row?.node.accessibilityLabel }
    override func accessibilityChildren() -> [Any]? { [] }
    override func isAccessibilityFocused() -> Bool { cell?.isAccessibilityFocused() ?? false }
    override func setAccessibilityFocused(_ focused: Bool) { cell?.setAccessibilityFocused(focused) }
    override func accessibilityPerformShowMenu() -> Bool { cell?.accessibilityPerformShowMenu() ?? false }
}

private final class StationAccessibilityColumn: NSAccessibilityElement {
    weak var outline: StationOutlineView?
    init(outline: StationOutlineView) { self.outline = outline; super.init() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .column }
    override func accessibilityParent() -> Any? { outline }
    override func accessibilityWindow() -> Any? { outline?.window }
    override func accessibilityTopLevelUIElement() -> Any? { outline?.window }
    override func accessibilityIndex() -> Int { 0 }
    override func accessibilityLabel() -> String? { outline?.outlineTableColumn?.title }
    override func accessibilityFrame() -> NSRect {
        guard let outline = outline, let window = outline.window else { return .zero }
        return window.convertToScreen(outline.convert(outline.visibleRect, to: nil))
    }
    override func accessibilityChildren() -> [Any]? {
        guard let outline = outline else { return [] }
        return (0..<outline.numberOfRows).compactMap { outline.accessibleRow(at: $0)?.cell }
    }
}
