import Foundation

/// OOM 日志管理器 — 兼容 iOS 10+
final class OOMLogger {
    
    static let shared = OOMLogger()
    
    // MARK: - Log Entry Model
    
    struct LogEntry: Codable {
        let sessionID: String
        let timestamp: String  // ISO 8601 字符串，避免 DateFormatter 兼容问题
        let event: String      // "start", "alloc", "stop"
        let blockIndex: Int
        let chunkMB: Double
        let totalMB: Double
        let holdTimeMS: Double
    }
    
    struct SessionSummary {
        let id: String
        let startTime: Date
        let endTime: Date
        let lastTotalMB: Double
        let lastBlockIndex: Int
        let chunkMB: Double
        let holdTimeMS: Double
        let wasOOM: Bool
        let entries: [LogEntry]
    }
    
    // MARK: - Private
    
    private let logFileName = "oom_test_log.jsonl"
    private let fileManager = FileManager.default
    private var currentSessionID: String = ""
    private var currentChunkMB: Double = 0
    private var currentHoldTimeMS: Double = 0
    
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()
    
    private lazy var displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        f.locale = Locale.current
        return f
    }()
    
    private var logFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(logFileName)
    }
    
    private init() {}
    
    // MARK: - Helpers
    
    func formatDate(_ date: Date) -> String {
        return displayDateFormatter.string(from: date)
    }
    
    private func now() -> String {
        return dateFormatter.string(from: Date())
    }
    
    private func parseDate(_ string: String) -> Date {
        return dateFormatter.date(from: string) ?? Date()
    }
    
    // MARK: - Write Methods
    
    func logTestStart(chunkSizeMB: Double, holdTimeMS: Double) {
        currentSessionID = UUID().uuidString
        currentChunkMB = chunkSizeMB
        currentHoldTimeMS = holdTimeMS
        
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: now(),
            event: "start",
            blockIndex: 0,
            chunkMB: chunkSizeMB,
            totalMB: 0,
            holdTimeMS: holdTimeMS
        )
        appendEntry(entry)
    }
    
    func logAllocation(blockIndex: Int, chunkMB: Double, totalMB: Double) {
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: now(),
            event: "alloc",
            blockIndex: blockIndex,
            chunkMB: chunkMB,
            totalMB: totalMB,
            holdTimeMS: currentHoldTimeMS
        )
        appendEntry(entry)
    }
    
    func logTestStop(totalMB: Double) {
        let entry = LogEntry(
            sessionID: currentSessionID,
            timestamp: now(),
            event: "stop",
            blockIndex: 0,
            chunkMB: currentChunkMB,
            totalMB: totalMB,
            holdTimeMS: currentHoldTimeMS
        )
        appendEntry(entry)
    }
    
    // MARK: - Read Methods
    
    func readAllEntries() -> [LogEntry] {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            return []
        }
        
        do {
            let data = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
            let decoder = JSONDecoder()
            
            return lines.compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: lineData)
            }
        } catch {
            return []
        }
    }
    
    func getLastSessionSummary() -> SessionSummary? {
        let entries = readAllEntries()
        guard !entries.isEmpty else { return nil }
        
        let grouped = Dictionary(grouping: entries) { $0.sessionID }
        
        guard let lastSession = grouped.values
            .sorted(by: { group1, group2 in
                let t1 = group1.map { self.parseDate($0.timestamp) }.max() ?? Date.distantPast
                let t2 = group2.map { self.parseDate($0.timestamp) }.max() ?? Date.distantPast
                return t1 > t2
            })
            .first else {
            return nil
        }
        
        return buildSummary(from: lastSession)
    }
    
    func getAllSessionSummaries() -> [SessionSummary] {
        let entries = readAllEntries()
        guard !entries.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: entries) { $0.sessionID }
        
        return grouped.values
            .compactMap { buildSummary(from: $0) }
            .sorted(by: { $0.startTime > $1.startTime })
    }
    
    func clearLogs() {
        try? fileManager.removeItem(at: logFileURL)
    }
    
    // MARK: - Private
    
    private func buildSummary(from sessionEntries: [LogEntry]) -> SessionSummary? {
        guard let first = sessionEntries.first else { return nil }
        
        let hasStop = sessionEntries.contains { $0.event == "stop" }
        let allocEntries = sessionEntries.filter { $0.event == "alloc" }
        let lastAlloc = allocEntries.max(by: { $0.totalMB < $1.totalMB })
        let startEntry = sessionEntries.first { $0.event == "start" }
        
        let startTime = parseDate(startEntry?.timestamp ?? first.timestamp)
        let endTime = sessionEntries.map { parseDate($0.timestamp) }.max() ?? startTime
        
        return SessionSummary(
            id: first.sessionID,
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
    
    private func appendEntry(_ entry: LogEntry) {
        let encoder = JSONEncoder()
        
        guard let jsonData = try? encoder.encode(entry),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        jsonString += "\n"
        
        guard let lineData = jsonString.data(using: .utf8) else { return }
        
        if fileManager.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                handle.synchronizeFile()
                handle.closeFile()
            }
        } else {
            try? lineData.write(to: logFileURL, options: .atomic)
        }
    }
}
