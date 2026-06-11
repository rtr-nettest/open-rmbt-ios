## Explanatory text on the Signal Measurement start screen

```gherkin
Feature: Signal Measurement start screen explains what the measurement does

  As a user opening the signal measurement (coverage) feature,
  I want the start screen to explain what the measurement does and
  what it requires, so that I can decide whether to start it before
  committing to a run.

  Background:
    Given I have opened the signal measurement feature
    And the measurement has not been started yet

  Scenario: Start screen presents title, explanation and actions
    When the start screen appears
    Then it shows the title "Signal Measurement"
    And it shows an explanatory paragraph describing that the
        measurement records mobile connectivity, technology and
        signal strength outdoors along a path, that it requires
        good GPS coverage with Wi-Fi turned off, that it uses much
        less data than a speed measurement, and that it is intended
        only for use within the EU/EEA
    And it shows a primary button to start the measurement
    And it shows a secondary button to cancel

  Scenario: Long explanation stays readable
    When the explanatory paragraph is longer than the available space
    Then the paragraph scrolls within the popup
    And the start and cancel buttons remain visible

  Scenario: Localization
    Given the device language is English
    Then the title and explanation are shown in English
    Given the device language is German
    Then the title and explanation are shown in German
```

## Notes

- The text is intentionally informational (no behavior change): it does not
  gate starting the measurement. Start availability is governed separately by
  the start-button rules — see `start-button-availability.md`.
- Copy source: rtr-nettest/open-rmbt-ios-private#86.

## References
- Sources/NetworkCoverage/NetworkCoverageView.swift (`testStartPopup`)
- Sources/NetworkCoverage/Components/TestPopup.swift
- Resources/{Base,en,de}.lproj/Localizable.strings — keys `coverage_intro_title`,
  `coverage_intro_description`, `coverage_intro_start_button`
