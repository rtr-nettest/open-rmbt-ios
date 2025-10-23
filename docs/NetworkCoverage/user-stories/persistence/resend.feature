Feature: Retrying submission of persisted fences
  As the iOS client
  I want to retry sending persisted fences
  So that results are eventually delivered when the network or server recovers

  Background:
    Given there are persisted fences from one or more tests

  Scenario: Retry on app start (cold start)
    When the app starts and settings/news are fetched
    Then the client calls resend of persisted fences
    And sends groups by testUUID with newest groups first

  Scenario: Retry on entering foreground (warm start)
    When the app enters foreground and settings/news are fetched
    Then the client calls resend of persisted fences

  Scenario: Retry before starting a new coverage session
    When a new /coverageRequest is initiated for coverage measurement
    Then the client calls resend of persisted fences

  Scenario: Retry after a successful submission of current test
    Given the client has successfully submitted the current test’s fences
    When submission completes
    Then the client attempts to resend any remaining persisted fences from other tests

  Scenario: Deleting old persisted fences before resend
    Given the default maximum resend age is 7 days
    When resend starts
    Then persisted fences older than 7 days are deleted

  Scenario: Grouping and ordering of resends
    Given persisted fences for multiple testUUIDs
    When resend runs
    Then groups are sorted by their earliest timestamp in descending order (latest first)
    And within each group, fences are sent in ascending timestamp order

  Scenario: Successful resend
    Given the server responds with HTTP 2xx for a group
    Then all persisted fences for that group’s testUUID are deleted

  Scenario: Failed resend
    Given the server responds with non-2xx or a transport error for a group
    Then persisted fences for that group remain for future retries

  # References:
  # - Sources/RMBTAppDelegate.swift: onStart/checkNews → resend
  # - Sources/NetworkCoverage/CoverageMeasurementSession/CoverageMeasurementSessionInitializer.swift:59–66 (resend before new session)
  # - Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift (session-based resend with TTL cleanup)
  # - RMBTTests/NetworkCoverage/Persistence/ResenderSessionBasedTests.swift
