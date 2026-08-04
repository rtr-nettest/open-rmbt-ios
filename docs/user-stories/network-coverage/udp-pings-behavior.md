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
  Scenario: UDP transport is strict on server source address
    Given the server responds to a UDP ping from the same IP address the client sent to
    When the client sends a UDP ping to the server address returned by ping_host
    Then the client shall only accept replies arriving from that destination address
    And response validity shall additionally be determined by protocol fields (RR01/RE01) and sequence number

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

  # No pings while on Wi-Fi
  Scenario: No pings are sent while the active path is Wi-Fi
    Given a coverage measurement is running
    When the active network path becomes Wi-Fi
    Then the app shall stop sending UDP pings
    And it shall not report any ping results, successful or failed
    And a ping that was already in flight when Wi-Fi appeared shall not be reported either

  Scenario: Returning from Wi-Fi refreshes the ping session
    Given a coverage measurement paused its pings because the active path was Wi-Fi
    When the active path becomes cellular again
    Then the app shall obtain a fresh ping session via /coverageRequest
    And it shall use the freshly returned ping_host, ping_port, ping_token and ip_version
    And the previous session shall keep sending pings until the new credentials arrive

  Scenario: A working ping does not settle an owed Wi-Fi refresh
    Given the app owes a ping session refresh because it returned from Wi-Fi
    And the refresh is still throttled by the recovery backoff
    When pings in the previous session keep succeeding
    Then the app shall still refresh the session once the backoff window elapses
    Because the previous session's ip_version may be wrong for the new path

  Scenario: Repeated Wi-Fi flapping does not create a session per flap
    Given a coverage measurement is running
    When the active path flaps between Wi-Fi and cellular several times within one backoff window
    Then the app shall create at most one new ping session in that window
    And the refresh owed by the remaining flaps shall be deferred, not lost

  Scenario: Starting a measurement on Wi-Fi creates exactly one session
    Given the active path is Wi-Fi when the measurement starts
    Then the app shall not call /coverageRequest while it stays on Wi-Fi
    When the active path becomes cellular
    Then the app shall create exactly one ping session, not one followed by a refresh

  # Recovery from a dead ping path
  Scenario: Recover the session after a run of failed pings
    Given a coverage measurement is running with a working ping session
    When 30 consecutive ping outcomes fail or time out (about 3 seconds at the 100 ms cadence)
    Then the app shall obtain a replacement ping session via /coverageRequest
    And the previous session shall keep sending and reporting pings until the replacement's credentials arrive

  Scenario: Do not recover while failures stay below the threshold
    Given a coverage measurement is running
    When fewer than 30 consecutive ping outcomes fail
    Or a ping succeeds before the threshold is reached
    Then the app shall keep using the current ping session

  Scenario: Throttle repeated recoveries with a doubling backoff
    Given the ping path stays broken
    Then the first recovery shall happen immediately
    And subsequent recoveries shall be spaced 10, 20, 40, 80 and then at most 120 seconds apart
    And a successful ping shall restart that ladder

  Scenario: A recovery attempt never silences the measurement
    Given a coverage measurement is running with a working ping session
    When a recovery attempt to /coverageRequest hangs or fails
    Then the attempt shall be abandoned after 15 seconds
    And the app shall continue using the previous ping session
    And it shall retry the recovery at the next backoff slot
    # The credentials fetch is bounded by 15 s; bringing the transport up is bounded by a tighter 5 s, because
    # that is the only window in which nothing can send.

  Scenario: Keep reporting failed pings while offline on cellular
    Given a coverage measurement is running on a cellular or unavailable path
    And no ping receives a response
    Then the app shall keep reporting failed pings
    So that the affected fences are rendered as "no coverage"

  # Pinning the ping transport to cellular
  Scenario: UDP pings are never carried over Wi-Fi
    Given a coverage measurement is running on a physical device
    When the app brings up the UDP ping transport
    Then the connection shall be constrained to a cellular interface
    And a connection that becomes ready on a path which also includes Wi-Fi shall be rejected
    So that a measurement can never be labelled cellular while carried over Wi-Fi
    # This is a guarantee, not a preference: the device-level Wi-Fi pause reads the *primary* path, so Wi-Fi that is
    # associated but not primary would otherwise leave it unaware.

  Scenario: The control request is not constrained to cellular
    Given the app needs a new ping session
    Then /coverageRequest may be carried over any interface, including Wi-Fi
    And the returned ip_version shall still be honoured for the UDP connection
    # Only the pings must be cellular. Because pings pause on Wi-Fi, /coverageRequest normally runs while cellular is
    # primary, and returning from a Wi-Fi epoch refreshes the session. That is not a refresh on every path change, so
    # a mismatched family remains possible; it shows up as repeated activation failures, not as a bad measurement.

  Scenario: No cellular path available at all
    Given a coverage measurement is running on a physical device
    And no cellular path can be used, for example behind a full-tunnel VPN
    Then the UDP transport shall fail to become ready
    And the app shall not keep requesting new sessions at the credentials-retry cadence
    And it shall report no pings rather than pings measured over another interface

  Scenario: Repeated transport activation failures back off
    Given a ping session's credentials were obtained successfully
    But the UDP transport cannot be brought up
    Then the first attempt shall be retried promptly
    And subsequent attempts shall be spaced by a doubling backoff, capped at the same maximum as recoveries
    And a successful activation shall restart that ladder
    # A single failure is usually transient (a handover), so it is not slowed down. Only a run of them indicates a
    # condition that will not clear on its own.

  Scenario: A failed credentials fetch does not inherit the activation backoff
    Given transport activation has already failed several times
    When a later /coverageRequest itself fails
    Then that failure shall be retried at the ordinary short retry delay
    And the activation backoff shall keep escalating independently
    # Missing credentials usually means the device is briefly offline and should be retried promptly; the two
    # conditions are unrelated and keep separate ladders.

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
