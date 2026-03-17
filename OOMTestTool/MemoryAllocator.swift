import Foundation
import os.log

/// 内存分配器 - 负责分步分配内存直到 OOM
final class MemoryAllocator: ObservableObject {
    
    // MARK: - Published State
    
    /// 当前已分配的总内存（MB）
    @Published var allocatedMB: Double = 0
    
    /// 当前分配的块数
    @Published var blockCount: Int = 0
    
    /// 是否正在运行测试
    @Published var isRunning: Bool = false
    
    /// 状态描述
    @Published var statusText: String = "就绪"
    
    /// 分配历史记录（用于界面展示）
    @Published var allocationHistory: [AllocationRecord] = []
    
    // MARK: - Configuration
    
    /// 单次分配大小（MB）
    var chunkSizeMB: Double = 10
    
    /// 每次分配后的保持时间（ms）
    var holdTimeMS: Double = 100
    
    // MARK: - Private
    
    /// 持有已分配的内存块，防止被释放
    private var memoryBlocks: [UnsafeMutableRawPointer] = []
    
    /// 工作队列
    private var workItem: DispatchWorkItem?
    
    private let logger = OOMLogger.shared
    
    // MARK: - Allocation Record
    
    struct AllocationRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let totalMB: Double
        let blockIndex: Int
    }
    
    // MARK: - Public Methods
    
    /// 开始内存压力测试
    func startTest() {
        guard !isRunning else { return }
        
        // 重置状态
        stopTest()
        isRunning = true
        allocatedMB = 0
        blockCount = 0
        allocationHistory = []
        statusText = "测试运行中..."
        
        // 记录测试开始
        logger.logTestStart(chunkSizeMB: chunkSizeMB, holdTimeMS: holdTimeMS)
        
        // 启动分配循环
        scheduleNextAllocation()
    }
    
    /// 停止测试并释放内存
    func stopTest() {
        workItem?.cancel()
        workItem = nil
        isRunning = false
        
        // 释放所有内存块
        for ptr in memoryBlocks {
            ptr.deallocate()
        }
        memoryBlocks.removeAll()
        
        if allocatedMB > 0 {
            statusText = "测试已停止，已释放 \(String(format: "%.1f", allocatedMB)) MB 内存"
            logger.logTestStop(totalMB: allocatedMB)
        } else {
            statusText = "就绪"
        }
        
        allocatedMB = 0
        blockCount = 0
    }
    
    // MARK: - Private Methods
    
    private func scheduleNextAllocation() {
        let item = DispatchWorkItem { [weak self] in
            self?.performAllocation()
        }
        workItem = item
        
        let delayMS = holdTimeMS
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .milliseconds(Int(delayMS)),
            execute: item
        )
    }
    
    private func performAllocation() {
        guard isRunning else { return }
        
        let byteCount = Int(chunkSizeMB * 1024 * 1024)
        
        // 分配内存
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        
        // 写入数据（确保物理内存被占用，而不是虚拟内存）
        // 用 0xAA 填充以确保每个页都被真正写入
        memset(ptr, 0xAA, byteCount)
        
        // 持有内存块
        memoryBlocks.append(ptr)
        
        let newBlockCount = memoryBlocks.count
        let newTotalMB = Double(newBlockCount) * chunkSizeMB
        
        // 写入日志（在分配后立即同步写入，确保 OOM 前记录）
        logger.logAllocation(
            blockIndex: newBlockCount,
            chunkMB: chunkSizeMB,
            totalMB: newTotalMB
        )
        
        // 更新 UI（主线程）
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            
            self.blockCount = newBlockCount
            self.allocatedMB = newTotalMB
            self.statusText = "已分配 \(String(format: "%.1f", newTotalMB)) MB（第 \(newBlockCount) 块）"
            
            let record = AllocationRecord(
                timestamp: Date(),
                totalMB: newTotalMB,
                blockIndex: newBlockCount
            )
            self.allocationHistory.append(record)
            
            // 只保留最近 50 条记录用于展示
            if self.allocationHistory.count > 50 {
                self.allocationHistory.removeFirst()
            }
        }
        
        // 继续下一次分配
        scheduleNextAllocation()
    }
    
    deinit {
        stopTest()
    }
}
