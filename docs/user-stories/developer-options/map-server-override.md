## Override the map server (developer option)

```gherkin
Feature: Custom map server override in developer mode

  As a developer,
  I want to point the map at a custom map server,
  so that I can test map tiles/filters/markers against a non-production server
  without rebuilding the app.

  The option mirrors the "Custom Control Server" override but has no SSL/port
  controls — only an on/off toggle and a hostname. When enabled with a valid
  hostname, every map request (tile template, tiles, markers, /v2/tiles/info)
  uses that host over https, keeping the resolved map path (e.g. /RMBTMapServer).

  Background:
    Given developer mode is enabled
    And the Settings screen shows the "Map server" section

  # --- Visibility ---------------------------------------------------------

  Scenario: The map server section is developer-only
    Given developer mode is disabled
    Then the "Map server" section is not shown

  Scenario: The hostname field appears only when the override is on
    Given the override is off
    Then only the "Override map server" toggle is shown
    When I turn the override on
    Then a hostname field appears below the toggle

  # --- Hostname validation ------------------------------------------------

  Scenario Outline: A valid hostname is accepted
    Given the override is on
    When I enter "<host>" and end editing
    Then the hostname is stored
    And the override stays on

    Examples:
      | host                 |
      | m04.netztest.at      |
      | m-cloud.netztest.at  |
      | a.b                  |

  Scenario Outline: An invalid hostname is discarded and the override is turned off
    Given the override is on
    When I enter "<host>" and end editing
    Then the hostname is cleared
    And the override is turned off

    Examples:
      | host            | reason          |
      |                 | empty           |
      | localhost       | no dot          |
      | map example.org | contains space  |
      | a.b,c.d         | contains comma  |

  # --- Effect on the map --------------------------------------------------

  Scenario: Map requests use the overridden host
    Given the override is on with host "m04.netztest.at"
    When the map loads
    Then map requests go to "https://m04.netztest.at/RMBTMapServer/..."

  Scenario: Changing the map server reloads the map
    Given the map is showing data from one map server
    When I change the override (toggle it, or change the hostname) and return to the map
    Then the map reloads its options, filters and tiles from the now-effective server
    And it does not keep the previous server's data

  Scenario: Disabling the override returns to the control-server-provided map server
    Given the override is on
    When I turn the override off and return to the map
    Then the map uses the map server from the control server's /settings response

  # --- Robustness (regression) --------------------------------------------

  Scenario: "All" filters do not crash the map
    Given a map filter value is "all" (sent as null, e.g. technology or operator)
    When a tile/marker URL is built
    Then the null value is omitted from the query string
    And the app does not crash
```

## Notes

- Toggle + hostname are built programmatically in `RMBTSettingsViewController`
  ("Map server" section). The hostname is validated on `editingDidEnd` by
  `RMBTSettingsViewController.isValidServerHostname(_:)`: non-empty, contains a
  dot, and no whitespace or commas. An invalid value clears
  `debugMapServerHostname` and sets `debugMapServerCustomizationEnabled = false`.
- The override only changes the host: `RMBTMapServer` swaps the host of the
  resolved map URL (forcing https, dropping any port, keeping the path), falling
  back to `https://<host>/RMBTMapServer` when settings haven't been fetched yet.
  Exposed as `RMBTMapServer.currentBaseURL`.
- The map re-validates on `viewWillAppear` by comparing the loaded base URL
  (`loadedMapServerBaseURL`) with `currentBaseURL`; on a mismatch it reloads
  options/filters/tiles. The Map is a persistent tab, so without this the old
  server's data would persist after a change.
- Regression: the tile/marker query-string builder previously force-cast values
  to `String` and crashed (`Could not cast value of type 'NSNull' to 'NSString'`,
  SIGABRT) for "all" filters that serialise to `NSNull` — exposed by a map server
  (m04) whose filter config emits null rather than empty strings. The builder now
  skips non-string/number values.

## References
- Sources/RMBTSettings.swift (`debugMapServerCustomizationEnabled`, `debugMapServerHostname`)
- Sources/RMBTSettingsViewController.swift ("Map server" section, `isValidServerHostname`)
- Sources/RMBTMapServer.swift (`currentBaseURL`, host-swap override, `queryString(from:)`)
- Sources/Map/RMBTMapViewController.swift (`loadedMapServerBaseURL`, reload-on-change)
- Sources/MainStoryboard.storyboard ("Custom Map Server" static section)
- RMBTTests/MapServerHostnameValidationTests.swift
- RMBTTests/RMBTMapServerQueryStringTests.swift
```
