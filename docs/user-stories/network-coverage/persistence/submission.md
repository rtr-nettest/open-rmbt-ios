Feature: Submitting coverage fences to ControlServer
  As the iOS client
  I want to submit fences for the currently active coverage sub-session
  So that the backend stores the complete result

  Background:
    Given a coverage measurement may span multiple server sessions
    And each fence may or may not have a sessionUUID assigned yet

  Scenario: Submit only fences matching the current session UUID
    Given the measurement has fences from previous and current server sessions in memory
    And the current session UUID is "T2"
    When the user stops the measurement
    Then the client submits POST /coverageResult containing only fences whose sessionUUID is "T2"

  Scenario: Successful submission
    Given the server responds with HTTP 2xx to /coverageResult
    Then the client treats the submission as successful
    And previously persisted fences for this test are cleared from persistence

  Scenario: Non-2xx submission response
    Given the server responds with HTTP status outside 200..299 to /coverageResult
    Then the client treats the submission as failed
    And previously persisted fences for this test remain in persistence

  Scenario: Current session has no matching fences
    Given the current session UUID is known
    And no in-memory fences match that UUID
    When the user stops the measurement
    Then the client skips direct submission for the current session
    And it triggers resend-only behavior for previously finalized persisted sessions

  Scenario: Measurement never obtained test_uuid
    Given the measurement is stopped before any /coverageRequest succeeds
    When the user stops the measurement
    Then direct submission fails because test_uuid is missing
    And the finalized nil-UUID persisted session is deleted locally
    And no /coverageResult request is sent for that session

References:
- Sources/NetworkCoverage/NetworkCoverageViewModel.swift (stop → send)
- Sources/NetworkCoverage/Persistence/PersistenceManagingCoverageResultsService.swift
- Sources/NetworkCoverage/SendResult/SendCoverageResultRequest.swift (payload mapping)
- Sources/RMBTControlServer.swift submitCoverageResult(acceptableStatusCodes: 200..<300)
