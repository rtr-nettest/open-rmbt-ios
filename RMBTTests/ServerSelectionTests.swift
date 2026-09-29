import Testing
import ObjectMapper
@testable import RMBT

// Developer-mode measurement server selection (server list from /settings, selection sent as prefer_server).
@Suite("Test server selection")
struct ServerSelectionTests {

    // MARK: - /settings servers parsing

    private func parseSettings(_ json: [String: Any]) -> SettingsResponse.Settings? {
        Mapper<SettingsResponse.Settings>().map(JSON: json)
    }

    @Test("WHEN settings has servers THEN each name and uuid is parsed")
    func whenSettingsHasServers_thenParsed() throws {
        let settings = try #require(parseSettings([
            "servers": [
                ["name": "Server A", "uuid": "uuid-a"],
                ["name": "Server B", "uuid": "uuid-b"],
            ]
        ]))
        let servers = try #require(settings.servers)
        #expect(servers.count == 2)
        #expect(servers[0].name == "Server A")
        #expect(servers[0].uuid == "uuid-a")
        #expect(servers[1].name == "Server B")
        #expect(servers[1].uuid == "uuid-b")
    }

    @Test("WHEN settings has no servers THEN servers is nil")
    func whenNoServers_thenNil() {
        #expect(parseSettings([:])?.servers == nil)
    }

    @Test("WHEN full response nests servers THEN parsed from the first settings entry")
    func whenFullResponseNestsServers_thenParsed() throws {
        let json: [String: Any] = [
            "settings": [
                ["uuid": "client-uuid", "servers": [["name": "S1", "uuid": "u1"]]]
            ]
        ]
        let response = Mapper<SettingsResponse>().map(JSON: json)
        #expect(response?.settings?.first?.servers?.first?.name == "S1")
        #expect(response?.settings?.first?.servers?.first?.uuid == "u1")
    }

    // MARK: - Persistence format (RMBTMeasurementServer <-> property-list dictionary)

    @Test("WHEN a server is round-tripped through its dictionary THEN it is unchanged")
    func whenRoundTrippedThroughDictionary_thenUnchanged() throws {
        let server = RMBTMeasurementServer(uuid: "u1", name: "Server One")
        let restored = try #require(RMBTMeasurementServer(dictionary: server.dictionaryValue))
        #expect(restored == server)
    }

    @Test("WHEN a persisted dictionary misses uuid or name THEN it does not decode")
    func whenDictionaryIncomplete_thenNil() {
        #expect(RMBTMeasurementServer(dictionary: ["name": "Server One"]) == nil)
        #expect(RMBTMeasurementServer(dictionary: ["uuid": "u1"]) == nil)
    }

    // MARK: - Test request server-selection fields (mirrors Android's user_server_selection / prefer_server)

    @Test("WHEN a specific server is selected THEN the request carries user_server_selection and prefer_server")
    func whenServerSelected_thenRequestCarriesFields() {
        let request = SpeedMeasurementRequest_Old()
        request.userServerSelection = true
        request.preferServer = "uuid-123"

        let json = request.toJSON()
        #expect(json["user_server_selection"] as? Bool == true)
        #expect(json["prefer_server"] as? String == "uuid-123")
    }

    @Test("WHEN the default server is used THEN the request omits prefer_server")
    func whenDefaultServer_thenNoPreferServer() {
        let request = SpeedMeasurementRequest_Old()
        request.userServerSelection = true
        request.preferServer = nil

        let json = request.toJSON()
        #expect(json["user_server_selection"] as? Bool == true)
        #expect(json["prefer_server"] == nil)
    }

    @Test("WHEN not in developer mode THEN the request omits both selection fields")
    func whenNotDeveloperMode_thenNoSelectionFields() {
        let request = SpeedMeasurementRequest_Old()
        let json = request.toJSON()
        #expect(json["user_server_selection"] == nil)
        #expect(json["prefer_server"] == nil)
    }
}
