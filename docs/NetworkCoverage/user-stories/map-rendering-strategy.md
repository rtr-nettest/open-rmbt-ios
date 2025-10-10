## Map rendering strategy for dense Network Coverage datasets

```gherkin
Feature: Adaptive map rendering for Network Coverage fences

  As a coverage analyst,
  I want the map to adapt rendering to fence density and viewport,
  so that large datasets stay responsive while remaining interpretable.

  Background:
    Given I am on the Network Coverage screen
    And the fences rendering configuration uses its default thresholds
    And the map camera region is shared with the coverage view model

  Scenario: Switch to polyline mode when zoomed out with many fences
    Given at least 60 fences are within the padded visible region
    And the visible region span is at least 0.03 degrees
    When the map reports the visible region
    Then the map render mode becomes "Polyline"
    And fences with the same technology are grouped into colored polyline segments

  Scenario: Revert to circle mode when zooming back in
    Given the map render mode is "Polyline"
    When the visible region span drops below 0.03 degrees
    Then the map render mode becomes "Circle"
    And individual fence circles are shown again

  Scenario: Clear selection when switching to polyline mode
    Given a fence is selected while the map render mode is "Circle"
    And zooming out causes at least 60 fences to enter the padded visible region
    When the map render mode switches to "Polyline"
    Then no fence remains selected

  Scenario: Keep current fence context in polyline mode
    Given a coverage measurement is running
    And the map render mode is "Polyline"
    When the current fence receives a new location update
    Then the current fence circle remains visible on the map

  Scenario: Cull off-screen fences for performance
    Given fences exist outside the visible region extended by 20 percent padding
    When the map reports the visible region
    Then fences outside the padded region are not rendered
    And polyline segments outside the padded region are hidden

  Scenario: Seed the visible region before camera callbacks arrive
    Given I open the read-only coverage history detail screen
    When fences are loaded before any map interaction
    Then the visible region is initialised to enclose all fences
    And the first rendered frame already shows the fences
```
