import AppKit

/// Identifies the app that sent a link, so rules can match on it.
enum SourceApp {
    private static let maxParentHops = 10
    private static let maxPathLength = 4096

    /// The bundle id of the sending process, or of its nearest regular (Dock-visible) ancestor.
    /// Falls back to the outermost `.app` bundle that contains the process's executable (helper processes).
    static func bundleId(forPID pid: pid_t) -> String? {
        var current = pid
        for _ in 0...maxParentHops {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular,
               let bundleId = app.bundleIdentifier {
                return bundleId
            }
            guard let parent = parentPID(of: current), parent > 1 else { break }
            current = parent
        }
        return bundleIdFromExecutablePath(of: pid)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func bundleIdFromExecutablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: maxPathLength)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        let bundlePath = String(path[..<range.lowerBound]) + ".app"
        return Bundle(path: bundlePath)?.bundleIdentifier
    }
}
