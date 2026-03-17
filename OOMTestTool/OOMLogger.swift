import Foundation

/// OOM 日志管理器 - 同步写入日志到文件，确保 OOM 前数据不丢失
final class OOMLogger {
    
    static let shared = OOMLogger()
    
    // MARK: - Log Entry Model
    
    struct LogEntry: Codable, Identifiable {
        var id: String { "\(sessionID)-\(blockIndex)" }
        let sessionID: String
        let timestamp: Date
        let event: String        // "start", "alloc", "stop"
        let blockIndex: Int
        let chunkMB: Double
        let totalMB: Double
        let holdTimeMS: Double
    }
    
    struct SessionSummary: Identifiable {
        let id: String  // sessionID
        let startTime: Date
        let endTime: Date
        let lastTotalMB: Double
        let lastBlockIndex: Int
        let chunkMB: Double
        let holdTimeMS: Double
        let wasOOM: Bool         // true = 没有正常 stop 日志
        let entries: [LogEntry]
        
        // iOS 13 兼容的时间格式化
        var endTimeFormatted: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: endTime)
        }
        
        var startTimeFormatted: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: startTime)
        }
    }
    
    // MARK: - Private
    
    private let logFileName = "oom_test_log.jsonl"
    private let fileManager = FileManager.default
    private var currentSessionID: String = ""
    private var currentChunkMB: Double = 0
    private var currentHoldTimeMS: Double = 0
    
    /// 日志文件路径
    private var logFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(logFileName)
    }
    
    private init() {}
    
    // MARK: - Write Methods
    
    /// 记录测试开始
    func logTestStart(chunkSizeMB: Double, holdTimeMS: Double) {
        currentSessionID = UUID().uuidString
        currentChunkMB = chunkSizeMB
        currentHoldTimeMS = holdTimeMS
        
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: Date(),
            event: "start",
            blockIndex: 0,
            chunkMB: chunkSizeMB,
            totalMB: 0,
            holdTimeMS: holdTimeMS
        )
        appendEntry(entry)
    }
    
    /// 记录一次内存分配
    func logAllocation(blockIndex: Int, chunkMB: Double, totalMB: Double) {
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: Date(),
            event: "alloc",
            blockIndex: blockIndex,
            chunkMB: chunkMB,
            totalMB: totalMB,
            holdTimeMS: currentHoldTimeMS
        )
        appendEntry(entry)
    }
    
    /// 记录测试正常停止
    func logTestStop(totalMB: Double) {
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: Date(),
            event: "stop",
            blockIndex: 0,
            chunkMB: currentChunkMB,
            totalMB: totalMB,
            holdTimeMS: currentHoldTimeMS
        )
        appendEntry(entry)
    }
    
    // MARK: - Read Methods
    
    /// 读取所有日志条目
    func readAllEntries() -> [LogEntry] {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            return []
        }
        
        do {
            let data = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return lines.compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: lineData)
            }
        } catch {
            print("读取日志失败: \(error)")
            return []
        }
    }
    
    /// 获取上次测试会话摘要（用于检查 OOM 崩溃）
    func getLastSessionSummary() -> SessionSummary? {
        let entries = readAllEntries()
        guard !entries.isEmpty else { return nil }
        
        // 按 session 分组
        let grouped = Dictionary(grouping: entries) { $0.sessionID }
        
        // 找到最近的 session（按时间排序）
        guard let lastSession = grouped.values
            .sorted(by: { group1, group2 in
                let t1 = group1.map(\.timestamp).max() ?? Date.distantPast
                let t2 = group2.map(\.timestamp).max() ?? Date.distantPast
                return t1 > t2
            })
            .first else {
            return nil
        }
        
        let sessionID = lastSession.first!.sessionID
        let hasStop = lastSession.contains { $0.event == "stop" }
        let allocEntries = lastSession.filter { $0.event == "alloc" }
        let lastAlloc = allocEntries.max(by: { $0.totalMB < $1.totalMB })
        
        let startEntry = lastSession.first { $0.event == "start" }
        let startTime = startEntry?.timestamp ?? lastSession.first!.timestamp
        let endTime = lastSession.map(\.timestamp).max() ?? startTime
        
        return SessionSummary(
            id: sessionID,
            startTime: startTime,
            endTime: endTime,
            lastTotalMB: lastAlloc?.totalMB ?? 0,
            lastBlockIndex: lastAlloc?.blockIndex ?? 0,
            chunkMB: startEntry?.chunkMB ?? lastAlloc?.chunkMB ?? 0,
            holdTimeMS: startEntry?.holdTimeMS ?? lastAlloc?.holdTimeMS ?? 0,
            wasOOM: !hasStop,
            entries: lastSession.sorted(by: { $0.timestamp < $1.timestamp })
        )
    }
    
    /// 获取所有会话摘要
    func getAllSessionSummaries() -> [SessionSummary] {
        let entries = readAllEntries()
        guard !entries.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: entries) { $0.sessionID }
        
        return grouped.values.compactMap { sessionEntries -> SessionSummary? in
            guard let first = sessionEntries.first else { return nil }
            
            let sessionID = first.sessionID
            let hasStop = sessionEntries.contains { $0.event == "stop" }
            let allocEntries = sessionEntries.filter { $0.event == "alloc" }
            let lastAlloc = allocEntries.max(by: { $0.totalMB < $1.totalMB })
            let startEntry = sessionEntries.first { $0.event == "start" }
            let startTime = startEntry?.timestamp ?? first.timestamp
            let endTime = sessionEntries.map(\.timestamp).max() ?? startTime
            
            return SessionSummary(
                id: sessionID,
                startTime: startTime,
                endTime: endTime,
                lastTotalMB: lastAlloc?.totalMB ?? 0,
                lastBlockIndex: lastAlloc?.blockIndex ?? 0,
                chunkMB: startEntry?.chunkMB ?? lastAlloc?.chunkMB ?? 0,
                holdTimeMS: startEntry?.holdTimeMS ?? lastAlloc?.holdTimeMS ?? 0,
                wasOOM: !hasStop,
                entries: sessionEntries.sorted(by: { $0.timestamp < $1.timestamp })
            )
        }
        .sorted(by: { $0.startTime > $1.startTime })
    }
    
    /// 清除所有日志
    func clearLogs() {
        try? fileManager.removeItem(at: logFileURL)
    }
    
    // MARK: - Private
    
    /// 同步追加一条日志（JSONL 格式，每行一个 JSON）
    private func appendEntry(_ entry: LogEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let jsonData = try? encoder.encode(entry),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        jsonString += "\n"
        
        guard let lineData = jsonString.data(using: .utf8) else { return }
        
        if fileManager.fileExists(atPath: logFileURL.path) {
            // 追加写入
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                // 强制刷盘，确保 OOM 前数据落地
                handle.synchronizeFile()
                handle.closeFile()
            }
        } else {
            // 创建新文件
            try? lineData.write(to: logFileURL, options: .atomic)
        }
    }
}
