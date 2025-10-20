Feature: Handling of HTTP status codes for /coverageResult
  As the iOS client
  I want strict success criteria for submissions
  So that only confirmed writes remove local persistence

  Scenario: Accept only 2xx as success
    Given a POST /coverageResult submission
    When the server responds with status 200..299
    Then the submission is considered successful

  Scenario: Treat non-2xx as failure and keep persisted data
    Given a POST /coverageResult submission
    When the server responds with status outside 200..299 (e.g., 406, 500)
    Then the submission is considered failed
    And persisted fences remain for future retry

  # References:
  # - Sources/NetworkCoverage/NetworkCoverageFactory.swift: acceptableSubmitResultsRequestStatusCodes = 200..<300
  # - Sources/RMBTControlServer.swift: submitCoverageResult(...acceptableStatusCodes:)

