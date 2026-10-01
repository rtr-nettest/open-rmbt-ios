import Testing
@testable import RMBT

// Mbit/s rounding, aligned with the Android client:
//   > 10 Mbit/s → full integer; <= 10 → two significant digits; expert mode → full value (3 decimals).
@Suite("Speed Mbit/s formatting")
struct RMBTSpeedFormatTests {

    private func mbps(_ kbps: Double, expert: Bool = false) -> String {
        RMBTSpeedMbpsString(kbps, withMbps: false, expertFullValue: expert)
    }

    @Test("WHEN above 10 Mbit/s THEN the full integer is shown (not 2 significant digits)")
    func aboveTenShowsFullInteger() {
        #expect(mbps(1_298_000) == "1298")   // not "1300"
        #expect(mbps(15_700) == "16")
        #expect(mbps(999_900) == "1000")
    }

    @Test("WHEN at or below 10 Mbit/s THEN two significant digits are kept")
    func upToTenKeepsTwoSignificantDigits() {
        #expect(mbps(10_000) == "10")   // 10.0 is not "above 10"
        #expect(mbps(9_870) == "9.9")
        #expect(mbps(5_230) == "5.2")
        #expect(mbps(500) == "0.50")
    }

    @Test("WHEN expert full value THEN the full value with three decimals is shown")
    func expertShowsFullValue() {
        // Decimal separator is locale-dependent (e.g. "1297,987" in de); normalise before comparing.
        func normalized(_ kbps: Double) -> String {
            mbps(kbps, expert: true).replacingOccurrences(of: ",", with: ".")
        }
        #expect(normalized(1_297_987) == "1297.987")
        #expect(normalized(5_230) == "5.230")
        #expect(normalized(1_298_000) == "1298.000")
    }
}
