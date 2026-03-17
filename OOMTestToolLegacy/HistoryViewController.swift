import UIKit

final class HistoryViewController: UITableViewController {
    
    private var sessions: [OOMLogger.SessionSummary] = []
    private let logger = OOMLogger.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "历史记录"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成",
            style: .done,
            target: self,
            action: #selector(dismissSelf)
        )
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SessionCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.backgroundColor = .systemGroupedBackground
        
        sessions = logger.getAllSessionSummaries()
        tableView.reloadData()
    }
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
    
    // MARK: - DataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sessions.isEmpty ? 1 : sessions.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions.isEmpty ? 1 : 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sessions.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "暂无测试记录"
            cell.textLabel?.textColor = .gray
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
            cell.selectionStyle = .none
            return cell
        }
        
        let session = sessions[indexPath.section]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SessionCell")
        cell.selectionStyle = .none
        
        // Build rich content
        let statusIcon = session.wasOOM ? "🔴" : "🟢"
        let statusText = session.wasOOM ? "OOM 崩溃" : "正常结束"
        
        cell.textLabel?.text = "\(statusIcon) \(statusText) — \(String(format: "%.1f", session.lastTotalMB)) MB"
        cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        if session.wasOOM {
            cell.textLabel?.textColor = .red
        } else {
            cell.textLabel?.textColor = UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        }
        
        let detail = "📦 \(session.lastBlockIndex) 块  |  📐 \(String(format: "%.0f", session.chunkMB)) MB/块  |  📅 \(logger.formatDate(session.startTime))"
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = .gray
        cell.detailTextLabel?.numberOfLines = 2
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !sessions.isEmpty else { return nil }
        return "Session \(section + 1)"
    }
}
