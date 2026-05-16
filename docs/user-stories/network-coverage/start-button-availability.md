## Start button availability on the intro screen for Network Coverage

```gherkin
Feature: Coverage measurement start button on the intro screen

  As a user who wants to measure network coverage,
  I want the "Start coverage" entry point to be available whenever
  it makes sense to capture coverage data — including when there is
  no mobile signal at all — but never on Wi-Fi, since Wi-Fi tells us
  nothing about cellular coverage.

  The button has exactly two visible states:
    * Green  → enabled, tapping starts a coverage measurement.
    * Gray   → disabled, tapping does nothing.

  Background:
    Given I am on the app intro screen
    And the minimum acceptable location accuracy is 15 meters

  # --- GPS gate (applies regardless of network type) ---------------------

  Scenario: Button is gray while no GPS fix is available
    Given the device has no location fix yet
    Then the start-coverage button is gray and disabled

  Scenario: Button is gray when GPS accuracy is worse than 15 meters
    Given the latest location accuracy is 15.001 meters or worse
    Then the start-coverage button is gray and disabled

  Scenario Outline: Button is green at the GPS accuracy boundaries
    Given the latest location accuracy is <accuracy> meters
    And the active network type is cellular
    Then the start-coverage button is green and enabled

    Examples:
      | accuracy |
      | 0.0      |
      | 15.0     |

  # --- Network gate (applies when GPS accuracy is good) ------------------

  Scenario: Button is gray on Wi-Fi
    Given the latest location accuracy is acceptable
    And the active network type is Wi-Fi
    Then the start-coverage button is gray and disabled

  Scenario Outline: Button is green on any non-Wi-Fi network state
    Given the latest location accuracy is acceptable
    And the active network type is <network>
    Then the start-coverage button is green and enabled

    Examples:
      | network                                          |
      | cellular                                         |
      | not yet known (no reachability callback yet)     |
      | unknown                                          |
      | none (offline)                                   |
      | browser (legacy hybrid context)                  |

  # --- Rationale -----------------------------------------------------------

  # The gate intentionally allows starting a coverage measurement when
  # there is no usable mobile signal: that is the very scenario from
  # issue #60 (start with no coverage, walk a route, anchor when
  # connectivity returns). Wi-Fi is the only state we forbid, because a
  # coverage run on Wi-Fi would produce no mobile-coverage information
  # by construction.
  #
  # Tint and enablement always agree: the button is green iff it is
  # tappable. There is no "green but disabled" or "gray but tappable"
  # combination.
```

## Notes

- Debug builds short-circuit the enablement check and always enable the button; the tint still tracks the real rule. This is a developer convenience and is not part of the user-visible contract.

## References
- Sources/NetworkCoverage/CoverageButtonGate.swift
- Sources/RMBTIntroViewController.swift (`updateCoverageTint`)
- RMBTTests/NetworkCoverage/CoverageButtonGateTests.swift
