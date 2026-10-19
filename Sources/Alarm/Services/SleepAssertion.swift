import Foundation
import IOKit.pwr_mgt

@MainActor
public final class SleepAssertionManager {
    public static let shared = SleepAssertionManager()
    
    private var assertionID: IOPMAssertionID = 0
    private var isAsserted: Bool = false
    
    private init() {}
    
    public func preventSleep(reason: String = "Alarm is ringing") {
        guard !isAsserted else { return }
        let assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        let success = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if success == kIOReturnSuccess {
            isAsserted = true
        }
    }
    
    public func releaseSleep() {
        guard isAsserted else { return }
        IOPMAssertionRelease(assertionID)
        isAsserted = false
        assertionID = 0
    }
}
