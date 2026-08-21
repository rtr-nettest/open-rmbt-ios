## Server-driven Signal Measurement availability via the settings response

```gherkin
Feature: Enable/disable the Signal Measurement feature from the control-server settings

  As the operator of the control server,
  I want the settings response to be able to turn the Signal Measurement
  (network coverage) feature on or off for a device,
  so that availability can be controlled centrally without the user having
  to enter the secret activation/deactivation code.

  This is an alternative path to the existing secret code. It reuses the same
  persisted flag (`coverageFeatureEnabled`) and therefore has the same effect
  on the intro screen's coverage entry point, with one difference: turning the
  feature on/off from the settings response shows NO confirmation popup (the
  secret code path shows one).

  The control server communicates availability through an optional boolean
  field `signal_measurement_available` in the settings response.

  Background:
    Given the app has been freshly installed
    Then the Signal Measurement feature is disabled by default

  Scenario: Settings response enables the feature
    Given the Signal Measurement feature is currently disabled
    When the settings response contains "signal_measurement_available" = true
    Then the Signal Measurement feature becomes enabled
    And the setting is persisted
    And no confirmation popup is shown
    And the intro screen's coverage entry point becomes available

  Scenario: Settings response disables the feature
    Given the Signal Measurement feature is currently enabled
    When the settings response contains "signal_measurement_available" = false
    Then the Signal Measurement feature becomes disabled
    And the setting is persisted
    And no confirmation popup is shown

  Scenario Outline: Settings response leaves the setting unchanged
    Given the Signal Measurement feature is currently <state>
    When the settings response <condition>
    Then the Signal Measurement feature remains <state>

    Examples:
      | state    | condition                                                  |
      | enabled  | does not contain the "signal_measurement_available" key    |
      | disabled | does not contain the "signal_measurement_available" key    |
      | enabled  | contains "signal_measurement_available" with a null value  |
      | disabled | contains "signal_measurement_available" with a null value  |

  # --- Relationship to the secret code -----------------------------------

  # The secret activation/deactivation code (entered in Settings) continues to
  # work and still shows its confirmation alert. Both paths write the same
  # persisted `coverageFeatureEnabled` flag, so the last signal — whichever
  # arrives — wins. The settings response is applied on every successful
  # settings fetch.
```

## Notes

- Three-state semantics come from an optional `Bool?` on the settings model:
  `true`/`false` change the persisted flag; a missing key or an explicit `null`
  parse to `nil` and leave the flag untouched.
- The backend contract is a JSON boolean. The value is parsed defensively so a
  stringified `"true"`/`"false"` (also `"1"`/`"0"`) still drives the flag; any
  other value is treated as "unset".
- Applying the flag posts `Notification.Name.RMBTCoverageAvailabilityChanged`
  so the intro screen refreshes its coverage entry point live.

## References
- Sources/Responses/Responses.swift (`SettingsResponse.Settings.signalMeasurementAvailable`, `BoolFromAnyTransform`)
- Sources/RMBTControlServer.swift (settings response handler, `RMBTCoverageAvailabilityChanged`)
- Sources/RMBTIntroViewController.swift (`coverageAvailabilityChanged`)
- Sources/Views/RMBTIntroPortraitView.swift (`updateCoverageUI`)
- Sources/RMBTSettingsViewController.swift (secret code path, for comparison)
- RMBTTests/SettingsResponseSignalMeasurementTests.swift
```
