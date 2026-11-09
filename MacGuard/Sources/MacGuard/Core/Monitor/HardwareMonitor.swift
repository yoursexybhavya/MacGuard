import Foundation
import Metal
import Darwin
import Combine

public struct HardwareInfo: Sendable, Equatable {
    public let chipName: String                  // e.g. "Apple M5 Pro", "Apple M1 Max"
    public let coreCount: Int                    // e.g. 15
    public let physicalMemoryBytes: UInt64       // e.g. 25769803776 (24 GB)
    public let formattedPhysicalMemory: String   // "24 GB"
    public let hasUnifiedMemory: Bool            // true for Apple Silicon
    public let activeResidentMemoryBytes: Int64  // Process resident RAM (bytes)
    public let formattedActiveRAM: String        // e.g. "146.7 MB"
    public let systemFreeMemoryBytes: Int64      // System free/inactive memory
    public let formattedSystemFree: String       // e.g. "4.8 GB Free"

    public var deviceSummary: String {
        if hasUnifiedMemory {
            return "\(chipName) • \(formattedPhysicalMemory) Unified"
        } else {
            return "\(chipName) • \(formattedPhysicalMemory)"
        }
    }

    public var activeMemorySummary: String {
        "Standalone Offline AI • \(formattedActiveRAM) Active"
    }

    public init(
        chipName: String,
        coreCount: Int,
        physicalMemoryBytes: UInt64,
        formattedPhysicalMemory: String,
        hasUnifiedMemory: Bool,
        activeResidentMemoryBytes: Int64,
        formattedActiveRAM: String,
        systemFreeMemoryBytes: Int64,
        formattedSystemFree: String
    ) {
        self.chipName = chipName
        self.coreCount = coreCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.formattedPhysicalMemory = formattedPhysicalMemory
        self.hasUnifiedMemory = hasUnifiedMemory
        self.activeResidentMemoryBytes = activeResidentMemoryBytes
        self.formattedActiveRAM = formattedActiveRAM
        self.systemFreeMemoryBytes = systemFreeMemoryBytes
        self.formattedSystemFree = formattedSystemFree
    }
}

@MainActor
public final class HardwareMonitor: ObservableObject {
    public static let shared = HardwareMonitor()

    @Published public private(set) var hardwareInfo: HardwareInfo
    private var refreshTimer: AnyCancellable?

    private init() {
        self.hardwareInfo = HardwareMonitor.queryHardware()
        startPeriodicRefresh()
    }

    public func refresh() {
        self.hardwareInfo = HardwareMonitor.queryHardware()
    }

    private func startPeriodicRefresh() {
        // Poll memory every 5 seconds on main runloop
        refreshTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    nonisolated public static func queryHardware() -> HardwareInfo {
        // 1. Metal Device Query
        let defaultDevice = MTLCreateSystemDefaultDevice()
        let allDevices = MTLCopyAllDevices()
        let primaryDevice = defaultDevice ?? allDevices.first
        let rawName = primaryDevice?.name ?? "Apple Silicon Metal"
        let hasUnified = primaryDevice?.hasUnifiedMemory ?? true

        // Clean device name if needed
        let chipName = rawName.isEmpty ? "Apple Silicon" : rawName

        // 2. CPU & Total Physical Memory
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let physicalBytes = ProcessInfo.processInfo.physicalMemory
        let formattedPhysical = ByteCountFormatter.string(fromByteCount: Int64(physicalBytes), countStyle: .memory)

        // 3. Process Resident Memory (mach_task_basic_info)
        var residentBytes: Int64 = 0
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            residentBytes = Int64(taskInfo.resident_size)
        }
        let formattedActive = residentBytes > 0
            ? ByteCountFormatter.string(fromByteCount: residentBytes, countStyle: .memory)
            : "0 MB Idle"

        // 4. System Free Memory (vm_statistics64)
        var freeBytes: Int64 = 0
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmKerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmKerr == KERN_SUCCESS {
            let pageSize = Int64(getpagesize())
            freeBytes = Int64(vmStats.free_count + vmStats.inactive_count) * pageSize
        }
        let formattedFree = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .memory) + " Free"

        return HardwareInfo(
            chipName: chipName,
            coreCount: cores,
            physicalMemoryBytes: physicalBytes,
            formattedPhysicalMemory: formattedPhysical,
            hasUnifiedMemory: hasUnified,
            activeResidentMemoryBytes: residentBytes,
            formattedActiveRAM: formattedActive,
            systemFreeMemoryBytes: freeBytes,
            formattedSystemFree: formattedFree
        )
    }
}
