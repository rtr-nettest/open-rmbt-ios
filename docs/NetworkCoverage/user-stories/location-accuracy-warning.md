## Location accuracy warning during Network Coverage measurement

```gherkin
Feature: Location accuracy warning during Network Coverage measurement

  As a user measuring network coverage,
  I want the app to warn me when GPS accuracy is insufficient,
  so that I can move outdoors or wait for better accuracy before continuing.

  Background:
    Given I am on the Network Coverage screen
    And the minimum acceptable location accuracy is 10 meters
    And the warning initial delay is 3 seconds

  Scenario: Warning is hidden before starting a measurement
    Given I have not started a measurement
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Warning remains hidden during the initial delay after starting
    When I start a measurement
    And 2.9 seconds pass
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Warning remains hidden if no location updates arrive after the delay
    When I start a measurement
    And no location updates are received
    And 3.1 seconds pass
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Warning is shown when the delay has elapsed and accuracy is bad
    When I start a measurement
    And 3.1 seconds pass
    And the latest location accuracy is worse than 10 meters
    Then the "Waiting for GPS" warning is displayed
    And the message reads "Currently the location accuracy is insufficient. Please measure outdoors."

  Scenario: Warning is hidden when the delay has elapsed and accuracy is good
    When I start a measurement
    And 3.1 seconds pass
    And the latest location accuracy is within 10 meters
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Stopping the measurement hides the warning
    Given the "Waiting for GPS" warning is displayed during a measurement
    When I stop the measurement
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Warning appears if accuracy worsens after being acceptable
    When I start a measurement
    And 3.1 seconds pass
    And the latest location accuracy is within 10 meters
    And later the latest location accuracy becomes worse than 10 meters
    Then the "Waiting for GPS" warning is displayed

  Scenario: Warning hides again if accuracy improves after being bad
    Given the "Waiting for GPS" warning is displayed during a measurement
    When the latest location accuracy becomes within 10 meters
    Then the "Waiting for GPS" warning is not displayed

  Scenario: Auto-stop and fail after 30 minutes without sufficient location accuracy
    When I start a measurement
    And 30 minutes pass
    And during this time no location update is within 10 meters
    Then the measurement is stopped automatically
    And the test result status is "Failed"
    And the failure reason is "Insufficient location accuracy for 30 minutes"
    And the "Waiting for GPS" warning is not displayed
```