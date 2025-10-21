Feature: Persisting coverage fences during and after a measurement
  As the iOS client
  I want to persist completed fences locally while measuring
  So that results survive app crashes and can be retried later

  Background:
    Given a running coverage measurement with fence radius 20 m

  # Current behavior per production code (NetworkCoverageViewModel)
  Scenario: Persist fence when user moves beyond the fence radius
    Given there is a current open fence
    And a precise location update increases distance >= 20 m from the fence start
    When the view model processes the location update
    Then the current fence is closed with exit time = update timestamp
    And the closed fence is saved to persistence
    And a new fence is opened at the new location

  Scenario: Persist the last open fence at stop()
    Given there is a current open fence without exit time
    When the user stops the measurement
    Then the last fence is closed with exit time set to now
    And the last fence is saved to persistence

  Scenario: Persisted fence fields
    When a fence is saved
    Then it includes testUUID of the current coverage session
    And timestamp is the fence enter time in microseconds since epoch
    And latitude/longitude are taken from the starting location
    And avgPingMilliseconds, technology, radiusMeters are stored when available

  # References:
  # - Sources/NetworkCoverage/NetworkCoverageViewModel.swift (closing + save on radius and stop)
  # - Sources/NetworkCoverage/Persistence/SwiftDataFencePersistenceService.swift
  # - docs/NetworkCoverage/sdd/network-coverage.md (Persistence & Result Submission)

