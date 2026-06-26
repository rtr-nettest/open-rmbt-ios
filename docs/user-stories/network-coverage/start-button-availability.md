## Start button availability on the intro screen for Network Coverage

```gherkin
Feature: Coverage measurement start button on the intro screen

  As a user who wants to measure network coverage,
  I want the "Start coverage" entry point to be available whenever
  it makes sense to capture coverage data — including when there is
  no mobile signal at all — but never on Wi-Fi, since Wi-Fi tells us
  nothing about cellular coverage.

  The button has exactly two visible states, but is always tappable:
    * Green  → available, tapping starts a coverage measurement.
    * Gray   → unavailable, tapping shows feedback explaining the
               requirements (Wi-Fi off and good GPS reception) instead
               of starting a measurement.

  Background:
    Given I am on the app intro screen
    And the minimum acceptable location accuracy is 15 meters

  # --- GPS gate (applies regardless of network type) ---------------------

  Scenario: Button is gray while no GPS fix is available
    Given the device has no location fix yet
    Then the start-coverage button is gray and unavailable

  Scenario: Button is gray when GPS accuracy is worse than 15 meters
    Given the latest location accuracy is 15.001 meters or worse
    Then the start-coverage button is gray and unavailable

  Scenario Outline: Button is green at the GPS accuracy boundaries
    Given the latest location accuracy is <accuracy> meters
    And the active network type is cellular
    Then the start-coverage button is green and available

    Examples:
      | accuracy |
      | 0.0      |
      | 15.0     |

  # --- Network gate (applies when GPS accuracy is good) ------------------

  Scenario: Button is gray on Wi-Fi
    Given the latest location accuracy is acceptable
    And the active network type is Wi-Fi
    Then the start-coverage button is gray and unavailable

  Scenario Outline: Button is green on any non-Wi-Fi network state
    Given the latest location accuracy is acceptable
    And the active network type is <network>
    Then the start-coverage button is green and available

    Examples:
      | network                                          |
      | cellular                                         |
      | not yet known (no reachability callback yet)     |
      | unknown                                          |
      | none (offline)                                   |
      | browser (legacy hybrid context)                  |

  # --- Feedback when unavailable (issue #95) -----------------------------

  Scenario: Tapping the gray button explains why coverage is unavailable
    Given the start-coverage button is gray and unavailable
    When I tap the start-coverage button
    Then I see feedback telling me that signal measurement requires
      Wi-Fi to be turned off and good GPS reception
    And no coverage measurement is started

  Scenario: Tapping the green button starts a measurement
    Given the start-coverage button is green and available
    When I tap the start-coverage button
    Then a coverage measurement starts
    And no feedback alert is shown

  # --- Rationale -----------------------------------------------------------

  # The gate intentionally allows starting a coverage measurement when
  # there is no usable mobile signal: that is the very scenario from
  # issue #60 (start with no coverage, walk a route, anchor when
  # connectivity returns). Wi-Fi is the only state we forbid, because a
  # coverage run on Wi-Fi would produce no mobile-coverage information
  # by construction.
  #
  # The button is always tappable; the tint communicates availability.
  # Green means tapping starts a measurement; gray means tapping shows
  # feedback explaining the unmet requirements (issue #95). This is the
  # only way a user learns why they cannot start while on Wi-Fi or
  # without a sufficient GPS fix.
```

## Notes

- The button is tappable in both states (green and gray). Earlier the gray button was inert and Debug builds force-enabled it as a developer convenience; that split was removed when issue #95 made the gray tap surface feedback in every build.

## References
- Sources/NetworkCoverage/CoverageButtonGate.swift
- Sources/RMBTIntroViewController.swift (`updateCoverageTint`)
- RMBTTests/NetworkCoverage/CoverageButtonGateTests.swift
