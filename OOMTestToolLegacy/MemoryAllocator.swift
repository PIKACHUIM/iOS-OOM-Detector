import Foundation

/// 内存分配器回调协议
protocol MemoryAllocatorDelegate: AnyObject {
    func allocatorDidUpdate(allocatedMB: Double, blockCount: Int, statusText: String)
    func allocatorDidFinish()
}

/// 内存分配器 — 纯 Foundation，兼容 iOS 10+
final class MemoryAllocator {
    
    weak var delegate: MemoryAllocatorDelegate?
    
    // MARK: - State
    
    private(set) var allocatedMB: Double = 0
    private(set) var blockCount: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var statusText: String = "就绪"
    
    // MARK: - Configuration
    
    var chunkSizeMB: Double = 10
    var holdTimeMS: Double = 100
    
    // MARK: - Private
    
    private var memoryBlocks: [UnsafeMutableRawPointer] = []
    private var workItem: DispatchWorkItem?
    private let logger = OOMLogger.shared
    
    // MARK: - Allocation Record (for UI log)
    
    struct AllocationRecord {
        let timestamp: Date
        let totalMB: Double
        let blockIndex: Int
    }
    
    private(set) var allocationHistory: [AllocationRecord] = []
    
    // MARK: - Public Methods
    
    func startTest() {
        guard !isRunning else { return }
        
        stopTest()
        isRunning = true
        allocatedMB = 0
        blockCount = 0
        allocationHistory = []
        statusText = "测试运行中..."
        
        logger.logTestStart(chunkSizeMB: chunkSizeMB, holdTimeMS: holdTimeMS)
        
        scheduleNextAllocation()
    }
    
    func stopTest() {
        workItem?.cancel()
        workItem = nil
        isRunning = false
        
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
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.allocatorDidFinish()
        }
    }
    
    // MARK: - Private Methods
    
    private func scheduleNextAllocation() {
        let item = DispatchWorkItem { [weak self] in
            self?.performAllocation()
        }
        workItem = item
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .milliseconds(Int(holdTimeMS)),
            execute: item
        )
    }
    
    private func performAllocation() {
        guard isRunning else { return }
        
        let byteCount = Int(chunkSizeMB * 1024 * 1024)
        
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        
        memset(ptr, 0xAA, byteCount)
        
        memoryBlocks.append(ptr)
        
        let newBlockCount = memoryBlocks.count
        let newTotalMB = Double(newBlockCount) * chunkSizeMB
        
        logger.logAllocation(
            blockIndex: newBlockCount,
            chunkMB: chunkSizeMB,
            totalMB: newTotalMB
        )
        
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
            if self.allocationHistory.count > 50 {
                self.allocationHistory.removeFirst()
            }
            
            self.delegate?.allocatorDidUpdate(
                allocatedMB: newTotalMB,
                blockCount: newBlockCount,
                statusText: self.statusText
            )
        }
        
        scheduleNextAllocation()
    }
    
    deinit {
        stopTest()
    }
}
