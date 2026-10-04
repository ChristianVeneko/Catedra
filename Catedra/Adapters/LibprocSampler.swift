import Foundation
import Darwin

/// Reads CPU time and resident size of a process tree through libproc (no subprocesses).
struct LibprocSampler: ProcessSampling {
    private static let timebase: (numer: Double, denom: Double) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (Double(info.numer), Double(max(info.denom, 1)))
    }()

    func snapshot(tree rootPID: Int32) -> [ProcessSnapshot] {
        guard let root = sample(rootPID) else { return [] }
        var result = [root]
        var visited: Set<Int32> = [rootPID]
        var queue = [rootPID]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            for child in children(of: parent) where visited.insert(child).inserted {
                if let s = sample(child) { result.append(s); queue.append(child) }
            }
        }
        return result
    }

    private func sample(_ pid: Int32) -> ProcessSnapshot? {
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { return nil }
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }
        // CPU times are in mach absolute time units (not nanoseconds on Apple Silicon).
        let ticks = Double(task.pti_total_user &+ task.pti_total_system)
        let seconds = ticks * Self.timebase.numer / Self.timebase.denom / 1_000_000_000
        let start = bsd.pbi_start_tvsec &* 1_000_000 &+ bsd.pbi_start_tvusec
        return ProcessSnapshot(pid: pid, startTime: start, cpuSeconds: seconds, rssBytes: task.pti_resident_size)
    }

    private func children(of pid: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 1024)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        // The return value is a byte count on some releases and an entry count on others: trust the zero fill instead.
        return buffer.prefix { $0 > 0 }.map { $0 }
    }
}
