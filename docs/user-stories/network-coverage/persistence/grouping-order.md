Feature: Grouping and ordering for resend
  As the iOS client
  I want deterministic resend ordering
  So that newest tests are prioritized and fence order remains chronological

  Scenario: Sort groups by recency
    Given persisted fences exist for tests A and B
    And the earliest fence timestamp for A is newer than B
    When resend runs
    Then test A is sent before test B

  Scenario: Sort fences within a group
    Given persisted fences for test A have timestamps t1 < t2 < t3
    When resend runs for test A
    Then the fences are sent in ascending timestamp order [t1, t2, t3]

References:
- Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift: sortedGroups and per-group sort

