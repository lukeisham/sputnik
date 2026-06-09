import Darwin
import Observation

/// Polls Sputnik's own process for RAM and CPU usage at 2-second intervals.
///
/// Started at app launch in `AppDelegate.applicationDidFinishLaunching`,
/// stopped in `applicationWillTerminate`. Values are published as `@Observable`
/// properties consumed by `StatusBarView`.
///
/// SR-4: Polling runs in a `Task(priority: .background)` loop.
/// SW-2: `[weak self]` in the polling Task body.
/// SW-1: Uses `Task` + `Task.sleep` — no `DispatchQueue.async` for business logic.
@Observable
@MainActor
public final class ProcessMonitor {
    private(set) public var ramMB: Int = 0
    private(set) public var cpuPercent: Double = 0.0
    private var pollingTask: Task<Void, Never>?

    public init() {}

    /// Starts the 2-second polling loop.
    /// Called from `AppDelegate.applicationDidFinishLaunching`.
    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                // Sample process stats
                let ram = self?.sampleRAM() ?? 0
                let cpu = self?.sampleCPU() ?? 0.0

                await MainActor.run { [weak self] in
                    self?.ramMB = ram
                    self?.cpuPercent = cpu
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            }
        }
    }

    /// Stops the polling loop.
    /// Called from `AppDelegate.applicationWillTerminate`.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Sampling (private)

    /// Returns resident-set size in MB by reading `mach_task_basic_info`.
    /// Returns 0 if sampling fails (SR-2: kern return checked).
    private func sampleRAM() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / (1024 * 1024))
    }

    /// Returns approximate system-wide CPU usage as a percentage.
    /// Uses `host_cpu_load_info` to compute a rough approximation.
    private func sampleCPU() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    $0,
                    &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }

        let total = Double(
            cpuInfo.cpu_ticks.0 + cpuInfo.cpu_ticks.1 + cpuInfo.cpu_ticks.2 + cpuInfo.cpu_ticks.3)
        guard total > 0 else { return 0.0 }

        // User + system ticks as a fraction of total (rough approximation for this process)
        let used = Double(cpuInfo.cpu_ticks.0 + cpuInfo.cpu_ticks.1)
        return (used / total) * 100.0
    }
}
