import Testing
import Foundation
@testable import GhafCore

@Suite struct SecurityPolicyTests {
    @Test func coversAppSwitcherWheneverSecurityLockIsEnabled() {
        #expect(GhafSecurityPolicy.shouldCoverAppSwitcher(sceneIsActive: false, lockEnabled: true))
        #expect(!GhafSecurityPolicy.shouldCoverAppSwitcher(sceneIsActive: true, lockEnabled: true))
        #expect(!GhafSecurityPolicy.shouldCoverAppSwitcher(sceneIsActive: false, lockEnabled: false))
    }

    @Test func autoLockUsesChosenBackgroundThreshold() {
        #expect(GhafSecurityPolicy.shouldLock(backgroundDuration: 0, delaySeconds: 0))
        #expect(!GhafSecurityPolicy.shouldLock(backgroundDuration: 59, delaySeconds: 60))
        #expect(GhafSecurityPolicy.shouldLock(backgroundDuration: 61, delaySeconds: 60))
        #expect(!GhafSecurityPolicy.shouldLock(backgroundDuration: 300, delaySeconds: 301))
        #expect(GhafSecurityPolicy.shouldLock(backgroundDuration: 301, delaySeconds: 300))
    }

    @Test func exportRequiresSuccessfulAuthentication() {
        #expect(!GhafSecurityPolicy.canExport(authenticated: false))
        #expect(GhafSecurityPolicy.canExport(authenticated: true))
    }
}
