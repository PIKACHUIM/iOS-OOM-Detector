import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var allocator = MemoryAllocator()
    
    @State private var chunkSizeText: String = "10"
    @State private var holdTimeText: String = "100"
    @State private var lastSession: OOMLogger.SessionSummary? = nil
    @State private var showHistory: Bool = false
    @State private var showClearAlert: Bool = false
    @State private var allSessions: [OOMLogger.SessionSummary] = []
    
    private let logger = OOMLogger.shared
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // 上次崩溃提醒
                    if let session = lastSession, session.wasOOM {
                        LastCrashBanner(session: session)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // 实时内存监控
                    if allocator.isRunning {
                        MemoryMonitorCard(allocator: allocator)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 参数配置卡片
                    ConfigurationCard(
                        chunkSizeText: $chunkSizeText,
                        holdTimeText: $holdTimeText,
                        isRunning: allocator.isRunning
                    )
                    
                    // 开始/停止按钮
                    ActionButton(
                        isRunning: allocator.isRunning,
                        onStart: startTest,
                        onStop: { allocator.stopTest(); loadLastSession() }
                    )
                    
                    // 状态文字
                    StatusBadge(text: allocator.statusText, isRunning: allocator.isRunning)
                    
                    // 实时分配日志
                    if !allocator.allocationHistory.isEmpty {
                        AllocationLogCard(history: allocator.allocationHistory)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OOM 测试工具")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            allSessions = logger.getAllSessionSummaries()
                            showHistory = true
                        } label: {
                            Label("历史记录", systemImage: "clock.arrow.circlepath")
                        }
                        
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Label("清除日志", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView(sessions: allSessions)
            }
            .alert("清除所有日志", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    logger.clearLogs()
                    lastSession = nil
                    allSessions = []
                }
            } message: {
                Text("确定要清除所有测试日志吗？此操作不可撤销。")
            }
        }
        .onAppear {
            loadLastSession()
        }
        .animation(.easeInOut(duration: 0.3), value: allocator.isRunning)
        .animation(.easeInOut(duration: 0.3), value: lastSession?.id)
    }
    
    // MARK: - Actions
    
    private func startTest() {
        let chunk = Double(chunkSizeText) ?? 10
        let hold = Double(holdTimeText) ?? 100
        
        allocator.chunkSizeMB = max(1, chunk)
        allocator.holdTimeMS = max(10, hold)
        allocator.startTest()
    }
    
    private func loadLastSession() {
        lastSession = logger.getLastSessionSummary()
    }
}

// MARK: - Last Crash Banner

struct LastCrashBanner: View {
    let session: OOMLogger.SessionSummary
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("检测到上次 OOM 崩溃")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                InfoRow(icon: "memorychip", label: "崩溃时内存",
                        value: "\(String(format: "%.1f", session.lastTotalMB)) MB",
                        tint: .white)
                InfoRow(icon: "number.square", label: "分配块数",
                        value: "\(session.lastBlockIndex) 块（每块 \(String(format: "%.0f", session.chunkMB)) MB）",
                        tint: .white)
                InfoRow(icon: "clock", label: "保持间隔",
                        value: "\(String(format: "%.0f", session.holdTimeMS)) ms",
                        tint: .white)
                InfoRow(icon: "calendar", label: "崩溃时间",
                        value: session.endTimeFormatted,
                        tint: .white)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.85), Color.orange.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Memory Monitor Card

struct MemoryMonitorCard: View {
    @ObservedObject var allocator: MemoryAllocator
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundColor(.green)
                
                Text("实时监控")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 运行指示器
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 4)
                    Text("运行中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 大字体显示当前内存
            VStack(spacing: 4) {
                Text(String(format: "%.1f", allocator.allocatedMB))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(memoryColor)
                
                Text("MB 已分配")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            
            Divider()
            
            // 详细信息
            HStack(spacing: 20) {
                StatItem(title: "块数", value: "\(allocator.blockCount)",
                         icon: "square.stack.3d.up")
                
                StatItem(title: "块大小", value: "\(String(format: "%.0f", allocator.chunkSizeMB)) MB",
                         icon: "square.split.2x2")
                
                StatItem(title: "间隔", value: "\(String(format: "%.0f", allocator.holdTimeMS)) ms",
                         icon: "timer")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
    
    private var memoryColor: Color {
        if allocator.allocatedMB > 500 {
            return .red
        } else if allocator.allocatedMB > 200 {
            return .orange
        } else {
            return .green
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Configuration Card

struct ConfigurationCard: View {
    @Binding var chunkSizeText: String
    @Binding var holdTimeText: String
    let isRunning: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text("测试参数")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 14) {
                // 单次分配大小
                HStack(spacing: 12) {
                    Label {
                        Text("单次分配")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "memorychip")
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        TextField("10", text: $chunkSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(isRunning)
                        
                        Text("MB")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 28)
                    }
                }
                
                Divider()
                
                // 保持时间
                HStack(spacing: 12) {
                    Label {
                        Text("保持时间")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundColor(.purple)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        TextField("100", text: $holdTimeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(isRunning)
                        
                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 28)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .opacity(isRunning ? 0.6 : 1.0)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        Button {
            if isRunning {
                onStop()
            } else {
                onStart()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.title3)
                
                Text(isRunning ? "停止测试" : "开始测试")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: isRunning
                        ? [Color.red, Color.red.opacity(0.8)]
                        : [Color.accentColor, Color.accentColor.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: (isRunning ? Color.red : Color.accentColor).opacity(0.4),
                radius: 8, y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Allocation Log Card

struct AllocationLogCard: View {
    let history: [MemoryAllocator.AllocationRecord]
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundColor(.purple)
                
                Text("分配日志")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("最近 \(history.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVStack(spacing: 6) {
                ForEach(history.reversed()) { record in
                    HStack {
                        Text("#\(record.blockIndex)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        
                        ProgressView(value: min(record.totalMB / 1024, 1.0))
                            .accentColor(progressColor(for: record.totalMB))
                        
                        Text("\(String(format: "%.1f", record.totalMB)) MB")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
    
    private func progressColor(for mb: Double) -> Color {
        if mb > 500 { return .red }
        if mb > 200 { return .orange }
        return .green
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .primary
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(tint.opacity(0.8))
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(tint.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(tint)
        }
    }
}

// MARK: - History View

struct HistoryView: View {
    let sessions: [OOMLogger.SessionSummary]
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无测试记录")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sessions) { session in
                            SessionRow(session: session)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: OOMLogger.SessionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // OOM 标记
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.wasOOM ? .red : .green)
                        .frame(width: 10, height: 10)
                    
                    Text(session.wasOOM ? "OOM 崩溃" : "正常结束")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(session.wasOOM ? .red : .green)
                }
                
                Spacer()
                
                Text(session.startTimeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                Label {
                    Text("\(String(format: "%.1f", session.lastTotalMB)) MB")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "memorychip")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                Label {
                    Text("\(session.lastBlockIndex) 块")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                
                Label {
                    Text("\(String(format: "%.0f", session.chunkMB)) MB/块")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "square.split.2x2")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
