## Signal-measurement readiness ("preparing") phase

This story describes the behaviour brought over from the Android app (see `ios.md`): after the user
commits to a signal (coverage) measurement, the app enters a **preparing** phase and does not record
any fences until the phone genuinely has a fresh, accurate GPS fix on a mobile (non–Wi‑Fi) network.
A readiness screen shows why it is waiting; recording then begins on its own.

```gherkin
Feature: Signal-measurement readiness (preparing) phase

  As a user measuring network coverage,
  I want recording to start only once my phone actually has an accurate GPS fix on a mobile network,
  so that measurements are not started under conditions that would produce meaningless data.

  Background:
    Given I have committed to starting a signal measurement
    And the minimum acceptable location accuracy is 15 meters
    And a location fix is considered fresh only if it is at most 60 seconds old

  Scenario: Entering the preparing phase
    When the measurement starts
    Then it enters the "preparing" phase
    And no fences are recorded yet
    And the readiness screen is shown with a GPS row and a Network row

  Scenario: Recording begins on a fresh, accurate fix on mobile
    Given the phone is on a mobile network
    When a fresh location fix within 15 meters arrives
    Then recording begins automatically
    And the first fence is created from that fix
    And the readiness screen is replaced by the live measurement screen

  Scenario: GPS accuracy insufficient
    Given the phone is on a mobile network
    When the latest fix is worse than 15 meters
    Then the measurement stays in the preparing phase
    And the GPS readiness row is not OK and reads "GPS: accuracy <n> m (limit 15 m)"

  Scenario: No GPS signal or a stale fix
    When there is no location fix, or the latest fix is older than 60 seconds
    Then the measurement stays in the preparing phase
    And the GPS readiness row is not OK and reads "GPS: no signal"

  Scenario: On Wi-Fi
    Given the active network is Wi-Fi
    When even a fresh, accurate fix arrives
    Then the measurement stays in the preparing phase
    And the Network readiness row is not OK and reads "Network: WiFi"

  Scenario: Both conditions good
    Given the phone is on a mobile network
    And a fresh fix within 15 meters is available
    Then the GPS readiness row is OK and reads "GPS: OK"
    And the Network readiness row is OK and reads "Network: <technology>"
    And recording begins

  Scenario: Waiting indefinitely (no preparing timeout)
    When the phone never gets a fresh, accurate fix on a mobile network
    Then the measurement keeps waiting in the preparing phase
    And it never records and reports no failure reason
    # There is intentionally no preparing timeout on either platform yet (see ios.md §3.8).

  Scenario: Aborting while preparing
    Given the measurement is in the preparing phase
    When I tap Abort
    Then the measurement stops
    And no session is started and nothing is persisted or sent
    And I return to the start screen

  Scenario: The same GPS stream continues into recording
    Given the measurement began recording after preparing
    Then the location stream used while preparing keeps running into recording
    And there is no cold GPS restart at the hand-off
```

### Relationship to the in-measurement warnings

The readiness rows replace the *pre-recording* GPS / Wi‑Fi warnings: while preparing, the reasons the
measurement cannot start are shown as readiness rows rather than as the in-measurement warning popups.
Once recording has begun (a good fix was obtained), the existing in-measurement warnings still apply if
conditions later degrade — see [location-accuracy-warning.md](location-accuracy-warning.md) and
[wifi-connection-warning.md](wifi-connection-warning.md).
