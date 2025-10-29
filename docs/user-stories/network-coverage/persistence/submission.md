Feature: Submitting coverage fences to ControlServer
  As the iOS client
  I want to submit all fences for a coverage test
  So that the backend stores the complete result

  Background:
    Given a coverage session has test_uuid from /coverageRequest

  Scenario: Submit all fences when the user stops the measurement
    Given the measurement has N >= 1 fences in memory
    When the user stops the measurement
    Then the client submits POST /coverageResult with a fences array of size N

  Scenario: Successful submission
    Given the server responds with HTTP 2xx to /coverageResult
    Then the client treats the submission as successful
    And previously persisted fences for this test are cleared from persistence

  Scenario: Non-2xx submission response
    Given the server responds with HTTP status outside 200..299 to /coverageResult
    Then the client treats the submission as failed
    And previously persisted fences for this test remain in persistence

References:
- Sources/NetworkCoverage/NetworkCoverageViewModel.swift (stop → send)
- Sources/NetworkCoverage/SendResult/SendCoverageResultRequest.swift (payload mapping)
- Sources/RMBTControlServer.swift submitCoverageResult(acceptableStatusCodes: 200..<300)

