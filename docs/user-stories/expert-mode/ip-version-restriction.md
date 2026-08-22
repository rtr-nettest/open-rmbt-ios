## Restrict the measurement to a single IP version (expert mode)

```gherkin
Feature: IPv4-only / IPv6-only measurement restriction in expert mode

  As an expert user,
  I want to restrict a measurement to IPv4 only or IPv6 only,
  so that I can test a specific IP version — but only when the current
  connection actually supports that version.

  Availability of each IP version is derived from the IP request performed
  on the start (intro) screen: a version is "available" when its IP request
  succeeded and returned an external address. Both NAT and non-NAT results
  count as available.

  Background:
    Given expert mode is enabled
    And the intro screen has performed its IP request

  # --- Mutual exclusivity -------------------------------------------------

  Scenario: Enabling IPv4-only disables IPv6-only
    Given IPv6-only is enabled
    And IPv4 is available on the current connection
    When I enable IPv4-only
    Then IPv4-only is enabled
    And IPv6-only is disabled

  Scenario: Enabling IPv6-only disables IPv4-only
    Given IPv4-only is enabled
    And IPv6 is available on the current connection
    When I enable IPv6-only
    Then IPv6-only is enabled
    And IPv4-only is disabled

  # --- Availability gate when enabling ------------------------------------

  Scenario: Cannot enable IPv4-only when IPv4 is unavailable
    Given IPv4 is not available on the current connection
    When I try to enable IPv4-only
    Then the restriction stays disabled
    And I see an alert explaining that IPv4 is not available on the current connection

  Scenario: Cannot enable IPv6-only when IPv6 is unavailable
    Given IPv6 is not available on the current connection
    When I try to enable IPv6-only
    Then the restriction stays disabled
    And I see an alert explaining that IPv6 is not available on the current connection

  Scenario: Turning off expert mode clears both restrictions
    Given IPv4-only or IPv6-only is enabled
    When I disable expert mode
    Then both IPv4-only and IPv6-only are disabled

  # --- Start-test gate ----------------------------------------------------

  Scenario Outline: Starting a test is allowed when the restricted version is available
    Given <restriction> is enabled
    And <version> is available on the current connection
    When I start a test
    Then the test starts normally

    Examples:
      | restriction | version |
      | IPv4-only   | IPv4    |
      | IPv6-only   | IPv6    |

  Scenario Outline: Starting a test is blocked when the restricted version is unavailable
    Given <restriction> is enabled
    And <version> is not available on the current connection
    When I start a test
    Then no test starts
    And I see the alert "IP version not available, check expert settings"

    Examples:
      | restriction | version |
      | IPv4-only   | IPv4    |
      | IPv6-only   | IPv6    |

  Scenario: No restriction always allows starting a test
    Given neither IPv4-only nor IPv6-only is enabled
    When I start a test
    Then the test starts normally

  # --- Defaults -----------------------------------------------------------

  Scenario: Restrictions are off by default
    Given a fresh install
    Then neither IPv4-only nor IPv6-only is enabled
```

## Notes

- The IPv6-only restriction is the expert-mode counterpart to the existing IPv4-only
  restriction. A separate debug-only IPv6 force (`debugForceIPv6`) still exists; at the
  socket / control-server layer, IPv6 is forced when `forceIPv6 || debugForceIPv6`.
- "Available" maps to `ConnectivityInfo.ipvX.connectionAvailable`, which is set from the
  start-page IP request (`getIpv4` / `getIpv6`) and is true for both NAT and non-NAT.
- Availability is cached process-wide in `RMBTIPVersionAvailability` and refreshed each
  time the intro screen completes a connectivity check.
- The start-test decision is a pure function,
  `RMBTIPVersionAvailability.restrictionSatisfied(forceIPv4:forceIPv6:ipv4Available:ipv6Available:)`.

## References
- Sources/RMBTSettings.swift (`forceIPv4`, `forceIPv6`)
- Sources/RMBTIPVersionAvailability.swift
- Sources/RMBTSettingsViewController.swift (switch bindings, availability gate, expert-mode reset)
- Sources/RMBTIntroViewController.swift (`ipVersionRestrictionSatisfied`, start-test alert)
- Sources/SocketUtils.swift, Sources/RMBTControlServer.swift, Sources/ConnectivityService.swift (IP-version forcing)
- RMBTTests/IPVersionRestrictionTests.swift
```
