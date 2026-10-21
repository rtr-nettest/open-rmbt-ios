## Fence detail tooltip on the signal measurement map

```gherkin
Feature: Detail tooltip for a selected fence

  As a user,
  I want a tooltip describing the fence (map point) I tapped,
  so that I can read the technology, timing, ping, signal and travel speed
  recorded there.

  The tooltip is shown for the selected fence during the live measurement, on
  the result screen, and in history. It always shows Date and Technology, and
  conditionally shows Ping, Signal and Velocity.

  # --- Always shown -------------------------------------------------------

  Scenario: Date and Technology are always shown
    Given a fence is selected
    Then the tooltip shows the fence's Date
    And it shows the fence's Technology in that technology's colour

  # --- Ping ---------------------------------------------------------------

  Scenario: Ping is shown only when an average ping was recorded
    Given a selected fence has an average ping
    Then the tooltip shows a "Ping:" row with the value in ms
    But when the fence has no average ping
    Then no "Ping:" row is shown

  # --- Signal (Android-only) ----------------------------------------------

  Scenario: Signal is shown only when the fence carries a signal value
    Given a selected fence has a signal value
    Then the tooltip shows a "Signal:" row formatted as "<value> dBm"

  Scenario: No signal row for iOS-measured fences
    Given a fence was measured on iOS (iOS does not record signal)
    Then the tooltip shows no "Signal:" row
    # Signal is populated only for coverage tests measured on Android and
    # synced into this device's history.

  # --- Velocity -----------------------------------------------------------

  Scenario: Velocity is shown in km/h, rounded to a whole number
    Given a selected fence has a travel speed of 11.5 m/s
    Then the tooltip shows a "Velocity:" row reading "41 km/h"
    # 11.5 m/s x 3.6 = 41.4 km/h, rounded; matches Android's Math.round(speedMps * 3.6)

  Scenario: Velocity is hidden when there is no valid speed
    Given a selected fence has no travel speed (null or a negative GPS reading)
    Then the tooltip shows no "Velocity:" row

  Scenario: Velocity is hidden below the walking-noise threshold
    Given a selected fence has a travel speed below 0.9 m/s
    Then the tooltip shows no "Velocity:" row
    # Below 0.9 m/s the GPS speed is dominated by standing/walking noise.

  Scenario: Velocity is shown at the threshold
    Given a selected fence has a travel speed of exactly 0.9 m/s
    Then the tooltip shows a "Velocity:" row reading "3 km/h"
```

## Notes

- Rendered in `FencesMapView.selectedFenceDetailView(_:)` from a `FenceDetail`
  value model, in the order Date, Technology, Ping, Signal, Velocity (Signal
  before Velocity mirrors Android's `item_coverage_marker_details` layout).
- `FenceDetail` exposes `signal` and `velocity` as display strings that are
  empty when the row must be hidden; the view shows a row only when the string
  is non-empty.
- **Signal** comes from `Fence.signal` (dBm). Only the Android client records
  signal, so it is populated only for Android-measured coverage tests synced
  into this device's history (open-data `speed_curve.fences[].signal`); it is
  always `nil` for iOS-measured fences, which therefore never show the row.
- **Velocity** derives from `Fence.velocityMetersPerSecond` — the most recent
  GPS fix's speed for a live measurement, or the server-provided per-fence speed
  (`speed`, m/s) carried on the location for history. It is shown only when the
  speed is present and `>= FenceDetail.minVelocityMetersPerSecond` (0.9 m/s),
  formatted as rounded integer km/h (`Int((speed * 3.6).rounded())`).
- See [[technology-legend]] for the companion legend overlay and
  [[loop-history-navigation]] for how history reaches this screen.

## References
- Sources/NetworkCoverage/Components/FencesMapView.swift (`selectedFenceDetailView`)
- Sources/NetworkCoverage/NetworkCoverageViewModel.swift (`FenceDetail`, velocity formatting)
- Sources/NetworkCoverage/Fence.swift (`signal`, `velocityMetersPerSecond`)
- Sources/History/Coverage/CoverageHistoryDetailService.swift (`convertFenceData` threading signal/speed)
- Sources/Responses/RMBTOpenDataResponse.swift (`FenceData.signal`, `FenceData.speedMetersPerSecond`)
- RMBTTests/NetworkCoverage/History/Coverage/CoverageHistoryDetailServiceTests.swift (`CoverageHistoryDetailServiceTests`, `FenceDetailDisplayTests`)
```
