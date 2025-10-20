Feature: Resend policy for warm foreground vs. cold start (crash/quit recovery)
  As the iOS client
  I must not resend persisted fences for an unfinished test during a warm foreground
  But I shall resend persisted fences for an unfinished test after a cold start
  So that partial submits are avoided during BG/FG, yet crash recovery still delivers data

  Background:
    Given PersistentCoverageSession exists per test_uuid with fields { testUUID, startedAt, finalizedAt? }

  Scenario: Warm foreground (onStart(false)) while a test is running
    Given a coverage measurement is currently active for test_uuid T
    And the session for T has finalizedAt = nil (unfinished)
    And some fences for T are already persisted
    When the app enters foreground (applicationWillEnterForeground → onStart(false)) and resend is triggered
    Then the client MUST NOT resend persisted fences for test_uuid T
    And it SHOULD log a skip reason (e.g., "Skip resend: unfinished test in warm foreground")

  Scenario: Cold start (onStart(true)) after crash/quit with unfinished test
    Given the app launches fresh (application:didFinishLaunching → onStart(true))
    And the session for test_uuid T has finalizedAt = nil (unfinished)
    And fences for T are persisted
    When resend runs on cold start
    Then the client SHOULD resend persisted fences for test_uuid T (crash/quit recovery)
    And the client SHOULD also resend fences for any finalized tests as usual

  Scenario: Warm foreground resends only finalized tests
    Given another test U has finalizedAt set (finished)
    And fences for U are persisted
    When resend is triggered in warm foreground (onStart(false)) or before a new coverageRequest
    Then the client resends fences for test U
    And the client does not resend fences for any unfinished test (finalizedAt = nil)

  Scenario: After stop() finalizes the current test
    Given the user stops the measurement for test_uuid T and finalization sets finalizedAt
    When the next resend is triggered (foreground or next start)
    Then the client resends all fences for test_uuid T (subject to normal success/failure handling)

  Notes:
  - Cold vs. warm is distinguished by AppDelegate: onStart(true) for didFinishLaunching, onStart(false) for willEnterForeground.
  - Finished vs. unfinished is determined solely by the presence of session.finalizedAt.
