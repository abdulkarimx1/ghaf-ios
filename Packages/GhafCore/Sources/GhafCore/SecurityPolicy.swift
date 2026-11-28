import Foundation

public enum GhafSecurityPolicy {
    public static func shouldLock(backgroundDuration: TimeInterval, delaySeconds: Int) -> Bool {
        delaySeconds <= 0 || backgroundDuration >= TimeInterval(delaySeconds)
    }

    public static func canExport(authenticated: Bool) -> Bool { authenticated }
}
