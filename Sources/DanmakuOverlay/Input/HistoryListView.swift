import AppKit

final class HistoryListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((Database.HistoryEntry) -> Void)?

    private let tableView = NSTableView()
    private var entries: [Database.HistoryEntry] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTable()
        configureScrollView()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload(entries: [Database.HistoryEntry]) {
        self.entries = entries
        tableView.reloadData()
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.backgroundColor = .clear
    }

    private func configureScrollView() {
        documentView = tableView
        hasVerticalScroller = true
        borderType = .noBorder
        drawsBackground = false
        heightAnchor.constraint(equalToConstant: 130).isActive = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("historyCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let text = textForEntry(entries[row])
        cell.textField?.stringValue = text
        cell.textField?.toolTip = text
        return cell
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < entries.count else { return }
        onSelect?(entries[row])
    }

    private func textForEntry(_ entry: Database.HistoryEntry) -> String {
        var parts = [entry.title]
        if entry.page > 1 || !entry.partTitle.isEmpty && entry.partTitle != entry.title {
            parts.append("P\(entry.page) \(entry.partTitle)")
        }

        let resume: String
        if let profile = Database.shared.loadSyncProfile(cid: entry.cid), profile.offset > 5 {
            resume = "上次看到 \(mmss(profile.offset))"
        } else {
            resume = "\(entry.danmakuCount) 条弹幕"
        }
        return "\(parts.joined(separator: " · ")) — \(resume) · \(relativeDay(entry.lastOpenedAt))"
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func mmss(_ time: Double) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
