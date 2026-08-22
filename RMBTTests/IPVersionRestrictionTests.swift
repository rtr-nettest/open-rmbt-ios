import Testing
@testable import RMBT

// User story: docs/user-stories/expert-mode/ip-version-restriction.md
@Suite("IP version restriction", .serialized)
struct IPVersionRestrictionTests {

    // MARK: - Start-test gating (restrictionSatisfied)

    @Test("when_noRestriction_then_startAlwaysAllowed")
    func when_noRestriction_then_allowed() {
        #expect(RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4: false, forceIPv6: false, ipv4Available: false, ipv6Available: false) == true)
    }

    @Test("when_ipv4OnlyAndIPv4Available_then_startAllowed")
    func when_ipv4Only_available_then_allowed() {
        #expect(RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4: true, forceIPv6: false, ipv4Available: true, ipv6Available: false) == true)
    }

    @Test("when_ipv4OnlyAndIPv4Unavailable_then_startBlocked")
    func when_ipv4Only_unavailable_then_blocked() {
        #expect(RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4: true, forceIPv6: false, ipv4Available: false, ipv6Available: true) == false)
    }

    @Test("when_ipv6OnlyAndIPv6Available_then_startAllowed")
    func when_ipv6Only_available_then_allowed() {
        #expect(RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4: false, forceIPv6: true, ipv4Available: false, ipv6Available: true) == true)
    }

    @Test("when_ipv6OnlyAndIPv6Unavailable_then_startBlocked")
    func when_ipv6Only_unavailable_then_blocked() {
        #expect(RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4: false, forceIPv6: true, ipv4Available: true, ipv6Available: false) == false)
    }

    // MARK: - Availability cache maps from the start-page IP request

    @Test("when_ipRequestHasBothExternals_then_bothAvailable")
    func when_bothExternal_then_bothAvailable() {
        var info = ConnectivityInfo()
        info.ipv4.connectionAvailable = true
        info.ipv6.connectionAvailable = true
        RMBTIPVersionAvailability.shared.update(with: info)
        #expect(RMBTIPVersionAvailability.shared.isAvailable(forRestriction: .ipv4Only) == true)
        #expect(RMBTIPVersionAvailability.shared.isAvailable(forRestriction: .ipv6Only) == true)
    }

    @Test("when_onlyIPv4Reachable_then_onlyIPv4Available")
    func when_onlyIPv4_then_onlyIPv4Available() {
        var info = ConnectivityInfo()
        info.ipv4.connectionAvailable = true
        info.ipv6.connectionAvailable = false
        RMBTIPVersionAvailability.shared.update(with: info)
        #expect(RMBTIPVersionAvailability.shared.isAvailable(forRestriction: .ipv4Only) == true)
        #expect(RMBTIPVersionAvailability.shared.isAvailable(forRestriction: .ipv6Only) == false)
    }
}
