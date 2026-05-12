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
    Given a previous session response carried loop_uuid "L1"
    When a new /coverageRequest is needed for reinitialization
    Then the request payload shall include loop_uuid set to "L1"
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

  # UDP transport requirements
  Scenario: UDP transport must be unconnected
    Given the server may respond to a UDP ping from a different IP address than the destination
    When the client sends a UDP ping to the server address returned by ping_host
    Then the client shall accept the reply regardless of which server source address it arrives from
    And response validity shall be determined only by protocol fields (RR01/RE01) and sequence number

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
    And any persisted fences from older sessions are resent in order of most recent finalization time first

  # Offline start & anchored offsets (current partial behavior)
  Scenario: Persist fences before a session UUID exists
    Given the app starts a coverage measurement while offline
    And the app collects some fences before it can initialize with the server
    Then those fences may exist under an unfinished persisted session without test_uuid

  Scenario: Use the session anchor for offset_ms after a late UUID assignment
    Given an unfinished persisted session contains fences collected before and after a later anchor time
    When test_uuid "T3" and anchor_at are assigned to that session
    Then resend shall encode fences collected before the anchor with negative offset_ms
    And resend shall encode fences collected after the anchor with positive offset_ms

  Scenario: Mid-measurement recovery when connectivity returns
    Given the app starts a coverage measurement while offline
    And NetworkCoverageFactory injects NetworkReachabilityOnlineStatusService into the session initializer
    When the initial /coverageRequest fails
    Then the OnlineAwareSessionInitializer suspends until reachability reports the device is online
    And on the next online emission the session initializer retries /coverageRequest
    And on success it emits a sessionInitialized event so the view model anchors the in‑memory session

  # Multiple sub-sessions submission (new)
  Scenario: Submit multiple sub-sessions in one user-visible measurement
    Given a coverage measurement runs long enough to reinitialize twice
    And the app obtains test_uuid values "T4", then "T5"
    When sending results
    Then the app submits two coverageResult requests
    And the first request contains fences belonging to "T4" with offsets relative to its own initialization
    And the second request contains fences belonging to "T5" with offsets relative to its own initialization
    And the current unfinalized session (if any) is not submitted until it is finalized

  # Finalized offline session without test_uuid (issue #60)
  Scenario: Preserve a finalized fully-offline session for later late anchoring
    Given the user stops a coverage measurement while the device never went online
    And the app never obtained a test_uuid for that session
    And the persisted session contains at least one fence
    When stopping the measurement
    Then the session is finalized locally and kept on disk (NOT discarded)
    And no /coverageResult request is sent yet

  Scenario: Resender anchors a fully-offline session once connectivity returns
    Given a finalized persisted session with fences but no test_uuid exists
    When the resender runs (cold launch, foreground, before a new test, or after a successful submission)
    And /coverageRequest succeeds
    Then the resender writes the new test_uuid and anchor_at = now() onto the persisted session
    And submits all fences with negative offset_ms relative to that anchor
    And on a 2xx response the session is deleted from persistence
    And on failure the session is kept for the next resend cycle

  Scenario: Multiple stranded offline sessions are anchored independently
    Given multiple finalized persisted sessions with fences and no test_uuid exist
    When the resender runs and /coverageRequest succeeds for each
    Then each session receives its own test_uuid via a separate /coverageRequest call
    And each is submitted with offsets relative to its own anchor

  Scenario: Stranded offline session aged beyond maxResendAge is dropped
    Given a finalized persisted session with fences but no test_uuid is older than maxResendAge (default 7 days)
    When the resender runs cleanup
    Then the session is deleted by the age-based cleanup before any anchoring is attempted
