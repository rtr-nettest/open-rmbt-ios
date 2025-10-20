Feature: Cleanup of stale persisted fences and session records
  As the iOS client
  I want to discard very old persisted fences and their session metadata
  So that the resend queue stays bounded and the session store remains lean

  Scenario: Delete fences older than the configured max age
    Given max resend age is 7 days (configurable)
    And there are persisted fences with timestamps older than 7 days
    When resend starts
    Then those old fences are deleted from persistence before any send attempts
    And only recent fences remain eligible for resend

  Scenario: Delete PersistentCoverageSession records older than the configured max age
    Given max resend age is 7 days (configurable)
    And there are PersistentCoverageSession records with startedAt older than 7 days
    And those sessions have no recent fences within the max age window
    When resend starts
    Then those old session records are deleted

  Scenario: Delete orphaned PersistentCoverageSession records
    Given there exist PersistentCoverageSession records without any associated fences
    When resend starts
    Then those orphan session records are deleted

  Scenario: Do not delete fences for an unfinished/current test
    Given there exists a PersistentCoverageSession for test_uuid T with finalizedAt = nil (unfinished)
    And fences for T exist in persistence
    When cleanup runs as part of resend
    Then fences for test_uuid T MUST NOT be deleted

  # References:
  # - Sources/NetworkCoverage/NetworkCoverageFactory.swift: acceptableSubmitResultsRequestStatusCodes, persistenceMaxAgeInterval = 7 days
  # - Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift: deleteOldPersistentFences()
  # - New helper: deleteOldPersistentCoverageSessions() to prune old/orphan sessions
  # - RMBTTests/NetworkCoverage/Persistence/FencePersistenceTests.swift (older-than-max-age deletion)
