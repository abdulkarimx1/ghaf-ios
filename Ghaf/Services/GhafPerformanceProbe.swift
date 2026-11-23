#if DEBUG
import Foundation
import OSLog
import QuartzCore

/// Debug-only timing for the navigation workload in GhafTabSpeedTests.
@MainActor
enum GhafPerformanceProbe {
    private static let logger = Logger(subsystem: "com.ghaf.app", category: "TabPerformance")
    private static let signposter = OSSignposter(logger: logger)
    private static var pending: (tab: Int, startedAt: CFTimeInterval, interval: OSSignpostIntervalState)?
    private static var visits: [Int: Int] = [:]
    private static var durations: [(tab: Int, visit: Int, milliseconds: Double)] = []
    private static var workDurations: [(name: String, visit: Int, milliseconds: Double)] = []

    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-GhafExportSpeedSignposts")
    }

    static func beginTransition(to tab: Int) {
        guard enabled else { return }
        if let pending { signposter.endInterval("TabAppearance", pending.interval) }
        let interval = signposter.beginInterval("TabAppearance", "tab=\(tab)")
        pending = (tab, CACurrentMediaTime(), interval)
    }

    @discardableResult
    static func endTransition(on tab: Int) -> String {
        guard enabled, let pending, pending.tab == tab else { return exportedReport }
        signposter.endInterval("TabAppearance", pending.interval, "tab=\(tab)")
        let visit = visits[tab, default: 0] + 1
        visits[tab] = visit
        durations.append((tab, visit, (CACurrentMediaTime() - pending.startedAt) * 1_000))
        self.pending = nil
        let report = exportedReport
        persistReport(report)
        return report
    }

    static func measure<Value>(_ name: String, operation: () -> Value) -> Value {
        guard enabled else { return operation() }
        let interval = signposter.beginInterval("MainThreadWork", "operation=\(name)")
        let startedAt = CACurrentMediaTime()
        let result = operation()
        signposter.endInterval("MainThreadWork", interval, "operation=\(name)")
        workDurations.append((name, workDurations.filter { $0.name == name }.count + 1,
                              (CACurrentMediaTime() - startedAt) * 1_000))
        persistReport(exportedReport)
        return result
    }

    static var exportedReport: String {
        let tabs = durations.map { "\($0.tab):\($0.visit):\(String(format: "%.2f", $0.milliseconds))" }
        let work = workDurations.map { "w:\($0.name):\($0.visit):\(String(format: "%.2f", $0.milliseconds))" }
        return (tabs + work).joined(separator: ",")
    }

    private static func persistReport(_ report: String) {
        logger.notice("GHAF_SPEED_REPORT \(report, privacy: .public)")
        if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? Data(report.utf8).write(to: cache.appendingPathComponent("ghaf-speed-signposts.txt"), options: .atomic)
        }
    }
}
#endif
