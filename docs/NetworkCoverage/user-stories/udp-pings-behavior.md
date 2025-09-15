Feature: UDP ping session behavior for RTR NetTest coverage

  Background:
    Given the app requests /coverageRequest to initialize a coverage session
    And the server responds with test_uuid, ping_token, ping_host, ping_port, ip_version
    And the server responds with max_coverage_session_seconds and max_coverage_measurement_seconds

  # Session lifecycle and chaining
  Scenario: Start first coverage measurement session
    When the app starts a new coverage measurement
    Then it shall use the provided ping_host, ping_port, and ping_token to initiate UDP pings
    And it shall remember test_uuid as the current session id

  Scenario: Chain sessions via loop_uuid on reinitialization
    Given a previous session with test_uuid "T1"
    When a new /coverageRequest is needed for reinitialization
    Then the request payload shall include loop_uuid set to "T1"
    And the response test_uuid shall become the new current session id

  # Timed reinitialization per measurement window
  Scenario: Reinitialize when per-session measurement time expires
    Given max_coverage_measurement_seconds is 120
    And a measurement session started at time t0
    When t >= t0 + 120 seconds
    Then the app shall transparently reinitialize the UDP ping session via /coverageRequest
    And it shall continue pinging without changing the UI state
    And it shall persist and send fences collected so far under the previous test_uuid

  # Total coverage session duration
  Scenario: Stop measurement when total session time expires
    Given max_coverage_session_seconds is 7200
    And coverage measurement started at time t0
    When t >= t0 + 7200 seconds
    Then the app shall stop the coverage measurement and show results

  # UDP packet protocol mapping (Appendix: Specification Ping)
  Scenario: Successful ping response (RR01)
    Given a UDP request was sent with protocol "RP01", a 32-bit sequence number, and the Base64 token
    When the device receives a UDP response with protocol "RR01" and the same sequence number
    Then the ping is considered successful and its duration is recorded

  Scenario: Error ping response (RE01) with matching sequence
    Given a UDP request was sent with protocol "RP01" and sequence number S
    When the device receives a UDP response with protocol "RE01" and sequence number S
    Then the ping is considered failed with needsReinitialization
    And the app shall reinitialize the UDP ping session before continuing

  Scenario: Error ping response (RE01) without matching sequence (e.g., 0x0)
    Given there is at least one pending ping request awaiting response
    When the device receives a UDP response with protocol "RE01" and sequence number 0x0
    Then all pending pings are failed with needsReinitialization
    And the app shall reinitialize the UDP ping session before continuing

  # UI behavior during reinitialization
  Scenario: UI remains uninterrupted during ping session reinitialization
    Given the app must reinitialize the ping session (due to timeout or RE01)
    When reinitialization occurs
    Then the app shall not display any special UI to the user
    And existing coverage fences remain visible
    And measurement proceeds seamlessly under the new session

  # Result submission behavior
  Scenario: Persist and submit completed fences
    Given fences were collected during a session with test_uuid "T1"
    And a reinitialization starts a new session with test_uuid "T2"
    When sending results
    Then fences collected under "T1" are submitted with test_uuid "T1"
    And any persisted fences from older sessions are resent in order of most recent first

