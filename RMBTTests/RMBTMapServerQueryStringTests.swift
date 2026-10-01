import Testing
import Foundation
@testable import RMBT

// Regression: map tile-URL params must tolerate NSNull (emitted for "all" filters like technology/operator).
// They were force-cast to String and crashed ("Could not cast value of type 'NSNull' to 'NSString'").
@Suite("Map server query string")
struct RMBTMapServerQueryStringTests {

    private func pairs(_ query: String) -> Set<String> {
        Set(query.split(separator: "&").map(String.init))
    }

    @Test("WHEN a param value is NSNull THEN it is skipped (no crash)")
    func nullValuesSkipped() {
        let query = RMBTMapServer.queryString(from: [
            "technology": NSNull(),
            "operator": NSNull(),
            "period": 180,
            "overlay_type": "heatmap"
        ])
        let result = pairs(query)
        #expect(result == ["period=180", "overlay_type=heatmap"])
    }

    @Test("WHEN values are strings or numbers THEN they are all included")
    func stringAndNumberIncluded() {
        let query = RMBTMapServer.queryString(from: [
            "map_options": "mobile/download",
            "statistical_method": 0.5,
            "map_type_is_mobile": 1
        ])
        #expect(pairs(query) == ["map_options=mobile/download", "statistical_method=0.5", "map_type_is_mobile=1"])
    }

    @Test("WHEN all values are null THEN the query string is empty")
    func allNullGivesEmpty() {
        #expect(RMBTMapServer.queryString(from: ["technology": NSNull(), "operator": NSNull()]).isEmpty)
    }
}
