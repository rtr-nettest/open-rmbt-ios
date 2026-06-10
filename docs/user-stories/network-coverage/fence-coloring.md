## Fence / point coloring on the Network Coverage map

```gherkin
Feature: Coloring coverage fences by technology and coverage quality

  As a coverage analyst,
  I want each fence/point colored by its radio technology, and greyed out when no
  real communication was possible,
  so that areas of "no coverage" are clearly distinguishable even when the device is
  still registered to a technology.

  Background:
    Given a coverage map is drawn
    And the same coloring rules apply during the test, after the test, and in history

  Scenario: Color a fence by its radio technology when communication succeeded
    Given a fence is registered to a radio technology
    And at least one ping succeeded in that fence
    When the fence is drawn on the map
    Then the fence uses the color of its significant radio technology

  Scenario: Grey out a fence with no connectivity
    Given a fence had no connectivity (the "no network" id 1000)
    When the fence is drawn on the map
    Then the fence is grey

  Scenario: Grey out a fence registered to a technology but with no successful ping
    Given a fence is registered to a radio technology
    And every recorded ping in that fence failed
    When the fence is drawn on the map
    Then the fence is grey
    # Background: under very bad coverage the device can be registered to a technology
    # (e.g. 4G) while no communication is possible — such points are "no coverage".

  Scenario: Keep technology color for a freshly opened fence with no ping result yet
    Given a fence is registered to a radio technology
    And the fence has not received any ping result yet
    When the fence is drawn on the map
    Then the fence keeps its technology color (it is pending, not no-coverage)

  Scenario: Turn grey as soon as the first ping result is a failure
    Given a fence is registered to a radio technology
    And its first ping result is a failure
    When the fence is drawn on the map
    Then the fence is grey

  Scenario: Treat a finalized fence with no recorded ping as no-coverage
    Given a finalized or historical fence is registered to a technology
    And it has no recorded average ping
    When the fence is reconstructed for drawing
    Then it is reconstructed with a failed ping and drawn grey

  Scenario: Do not grey out points invalidated by a changed IP
    Given a ping failed because the IP changed
    Then that ping triggers a session reinitialisation and is never recorded as a result
    And it therefore does not by itself cause the fence to be drawn grey

  Scenario: Split polyline segments when coverage changes within one technology
    Given the map render mode is "Polyline"
    And consecutive fences share the same technology
    But some of them have no successful ping
    When polyline segments are generated
    Then the run splits into a technology-colored segment and a grey (no-coverage) segment
```
