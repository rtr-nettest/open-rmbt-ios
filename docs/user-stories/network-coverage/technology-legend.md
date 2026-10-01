## Technology legend on the signal measurement map

```gherkin
Feature: Map legend of the technologies used in a signal measurement

  As a user,
  I want a legend of the radio technologies used in a signal measurement,
  so that I can read the coloured points/segments on the map.

  The legend sits in the bottom-left corner and is shown during the live
  measurement, on the result screen, and in history. It lists only the
  technologies actually used, each with the technology's colour.

  # --- Contents -----------------------------------------------------------

  Scenario: Only technologies actually used are listed, once each, in a fixed order
    Given a measurement used 5G SA, 4G and 3G points (some technologies repeated)
    Then the legend has one entry per distinct technology
    And they are ordered 2G, 3G, 4G, 5G NSA, 5G SA
    And each entry uses that technology's base colour

  Scenario: No grey "no service" entry
    Given some fences had no connectivity (no technology)
    Then those fences add no legend entry

  Scenario: A technology used but without coverage is still listed
    Given a fence used 4G but every ping failed (drawn grey on the map)
    Then the legend still lists "4G" with the 4G colour

  # --- Live updates -------------------------------------------------------

  Scenario: The legend updates only when a new technology appears
    Given a live measurement is running
    When a new fence arrives with a technology already in the legend
    Then the legend is not redrawn
    When a fence arrives with a technology not yet in the legend
    Then the legend adds that technology

  Scenario: Empty legend is hidden
    Given no technology has been recorded yet
    Then no legend is shown
```

## Notes

- Built in `NetworkCoverageViewModel.updateLegendIfNeeded()` from the fences'
  `significantTechnology.radioTechnologyDisplayValue`, excluding nil / "N/A" / "--".
  Colours come from `Color(technology:)` (the base technology colour, not the
  grey no-coverage colour). Fixed order via `legendRank`.
- `legendEntries` is only reassigned when the set changes, so SwiftUI redraws the
  legend when a new technology arrives, not on every fence.
- Rendered bottom-left in `FencesMapView` (lifted above the Apple Maps attribution),
  passed through for the live (`NetworkCoverageView`), result (`TestCoverageResultView`)
  and history (`CoverageResultView`) screens.

## References
- Sources/NetworkCoverage/NetworkCoverageViewModel.swift (`CoverageLegendEntry`, `legendEntries`, `updateLegendIfNeeded`, `legendRank`, `Color(technology:)`)
- Sources/NetworkCoverage/Components/FencesMapView.swift (legend overlay)
- Sources/NetworkCoverage/{NetworkCoverageView,CoverageResultView}.swift, Sources/History/Coverage/* (call sites)
- RMBTTests/NetworkCoverage/NetworkCoverageViewModelTests.swift (legend tests)
```
