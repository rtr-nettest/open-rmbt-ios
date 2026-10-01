## Signal-measurement loop history navigation

```gherkin
Feature: Viewing a signal-measurement loop and its segments in history

  As a user,
  I want to open a whole signal-measurement loop from history and drill into
  its individual segments,
  so that I can see the complete measurement and inspect each part.

  A loop (one "measurement") is recorded as one or more segments, each a separate
  open_test_uuid (segments are split at ~400 fences). History shows the loop with
  its total number of fences/points.

  # --- Multi-segment loop -------------------------------------------------

  Scenario: Opening a multi-segment loop shows the whole measurement
    Given a loop with several segments
    When I tap the loop entry in history
    Then I see one map with the fences of all segments aggregated
    And a "Details" button at the bottom

  Scenario: Details lists the segments
    Given I am on the whole-loop map
    When I tap "Details"
    Then I see the list of segments that make up the loop, latest first

  Scenario: Selecting a segment shows its result
    Given I am on the segment list
    When I select a segment
    Then I see that segment's map with the "Test details" button (the existing single-segment screen)

  Scenario: Back navigation unwinds step by step
    Given I drilled from history -> whole-loop map -> segment list -> a segment result
    When I navigate back repeatedly
    Then I return to the segment list, then the whole-loop map, then the history overview

  # --- Single-segment loop (unchanged) ------------------------------------

  Scenario: A single-segment measurement opens its result directly
    Given a measurement consisting of a single segment
    When I tap it in history
    Then I see that segment's map with "Test details" directly (no whole-loop map, no list)
```

## Notes

- Whole-loop map: `CoverageWholeLoopMapView` aggregates fences across all the loop's
  open_test_uuids (`CoverageHistoryDetailService.loadAggregatedFences(for:)`, failed
  segments skipped) and shows a "Details" button.
- Segment list: `CoverageLoopSegmentsListView`, latest first; a row opens the existing
  single-segment `CoverageHistoryDetailView` (map + "Test details").
- Navigation is wired in `RMBTHistoryIndexViewController`: a coverage series' header tap
  calls `presentCoverageWholeLoop` -> `presentCoverageSegmentList` -> `presentCoverageDetail`
  (UIKit pushes, so Back unwinds automatically). A single-segment loop still goes straight
  to `presentCoverageDetail`.
- The whole-loop map also shows the technology legend (aggregated across segments).

## References
- Sources/History/Coverage/CoverageWholeLoopMapView.swift
- Sources/History/Coverage/CoverageLoopSegmentsListView.swift
- Sources/History/Coverage/CoverageHistoryDetailView.swift (single segment)
- Sources/History/Coverage/CoverageHistoryDetailService.swift (`loadAggregatedFences`)
- Sources/History/RMBTHistoryIndexViewController.swift (presentCoverageWholeLoop / SegmentList / Detail)
```
