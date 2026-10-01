## Mbit/s rounding on speed displays

```gherkin
Feature: Rounding of Mbit/s speed values

  As a user,
  I want speed values shown with sensible precision,
  so that large speeds keep their magnitude and small speeds stay readable.

  Rounding is aligned with the Android client.

  # --- Normal display (everywhere: live gauge, S-curve value, final result) ---

  Scenario: Above 10 Mbit/s shows the full number
    Given a speed of 1298 Mbit/s
    Then it is shown as "1298"   # not rounded to two significant digits ("1300")

  Scenario Outline: Values above 10 round to a whole number
    When the speed is <mbps> Mbit/s
    Then it is shown as "<shown>"

    Examples:
      | mbps | shown |
      | 15.7 | 16    |
      | 999.9| 1000  |

  Scenario Outline: Values at or below 10 keep two significant digits
    When the speed is <mbps> Mbit/s
    Then it is shown as "<shown>"

    Examples:
      | mbps | shown |
      | 10.0 | 10    |
      | 9.87 | 9.9   |
      | 5.23 | 5.2   |
      | 0.5  | 0.50  |

  # --- Expert mode (final result only) ------------------------------------

  Scenario: Expert mode shows the full value on the final result
    Given expert mode is enabled
    And a final download/upload result of 1297.987 Mbit/s
    Then it is shown with full precision, e.g. "1297.987" ("1297,987" in locales using a comma)
    And not the rounded "1298"

  Scenario: Non-final (live) values are unaffected by expert mode
    Given expert mode is enabled
    When a live (intermediate) speed is shown
    Then it uses the normal rounding, not the full value
```

## Notes

- Central formatter: `RMBTSpeedMbpsString(_:withMbps:expertFullValue:)` in `Sources/Speed.swift`.
  - `expertFullValue` → three decimals, no grouping, locale decimal separator (mirrors Android
    `expertFormat()` = `DecimalFormat("####0.000")`).
  - above 10 Mbit/s → integer (`String(Int(mbps.rounded()))`).
  - up to 10 Mbit/s → two significant digits (`RMBTHelpers.RMBTFormatNumber`, unchanged).
- Expert full value is applied to the final result on the test screen
  (`RMBTTestViewController.updateSpeedLabel` when `isFinal` and `RMBTSettings.expertMode`) and to the
  result-review / history detail (`RMBTHistoryResult` detail parsing, gated on `RMBTSettings.expertMode`),
  matching Android, where `format()` is used everywhere and `expertFormat()` only on the result screen.
- `RMBTFormatNumber` (two significant digits) is still used for other values (e.g. ping in ms) and is
  left unchanged.

## References
- Sources/Speed.swift (`RMBTSpeedMbpsString`, `RMBTSpeedExpertFormatter`)
- Sources/Test/RMBTTestViewController.swift (`updateSpeedLabel`, expert gate on `isFinal`)
- Sources/RMBTHistoryResult.swift (result-detail download/upload, expert gate)
- Sources/RMBTHelpers.swift (`RMBTFormatNumber`)
- RMBTTests/RMBTSpeedFormatTests.swift
```
