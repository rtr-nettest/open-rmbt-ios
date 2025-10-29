## Wi‑Fi connection warning during Network Coverage measurement

```gherkin
Feature: Wi‑Fi connection warning during Network Coverage measurement

  As a user measuring network coverage,
  I want the app to block measurements while connected to Wi‑Fi
  so that results reflect cellular coverage only.

  Background:
    Given I am on the Network Coverage screen

  Scenario: Warning is hidden before starting a measurement
    Given I have not started a measurement
    Then the "Disable Wi-Fi" warning is not displayed

  Scenario: Warning appears when Wi‑Fi is detected
    When I start a measurement
    And the network connection type becomes Wi‑Fi
    Then the "Disable Wi-Fi" warning is displayed
    And the message reads "Please turn off Wi‑Fi to measure cellular coverage."

  Scenario: Location and ping updates are ignored while on Wi‑Fi
    Given a measurement is running
    And the network connection type is Wi‑Fi
    When location updates arrive
    And ping updates arrive
    Then they are ignored and do not affect fences or latest ping

  Scenario: Warning hides and measurement resumes when switching back to cellular
    Given the "Disable Wi-Fi" warning is displayed during a measurement
    When the network connection type becomes Cellular
    Then the "Disable Wi-Fi" warning is not displayed
    And subsequent location and ping updates are processed normally

  Scenario: Both Wi‑Fi and GPS warnings can be shown at the same time
    Given the network connection type is Wi‑Fi during a measurement
    And a location update arrives with accuracy worse than 10 meters
    And the GPS warning delay has elapsed
    Then the "Disable Wi‑Fi" warning is displayed
    And the "Waiting for GPS" warning is displayed
```
