## Choose the measurement server (developer option)

```gherkin
Feature: Developer-mode measurement server selection

  As a developer,
  I want to pick which measurement server a test uses,
  so that I can target a specific server instead of the control server's default.

  The selectable servers come from the control server's /settings response
  ("servers": [{ name, uuid }]). The choice is persisted and sent with the test
  request. Mirrors the Android client (user_server_selection / prefer_server).

  Background:
    Given developer mode is enabled

  # --- Settings UI --------------------------------------------------------

  Scenario: The server selection row is developer-only
    Given developer mode is disabled
    Then the Settings screen shows no "Server selection" row

  Scenario: Selecting a server
    Given developer mode is enabled
    And the Settings "Server selection" row shows the current choice ("Default" when none)
    When I open it
    Then I see "Default" plus one radio row per offered server
    When I pick a server
    Then it becomes the selected server
    And the start screen shows "Server: <name>"

  Scenario: Choosing Default clears the selection
    Given a specific server is selected
    When I pick "Default"
    Then no server override is set
    And the start screen shows no "Server:" label
    And the app does not crash   # regression: clearing persisted nil must not store NSNull

  # --- Test request -------------------------------------------------------

  Scenario: A selected server is sent with the test request
    Given developer mode is on and a server with uuid "u1" is selected
    When a test request is built
    Then it carries user_server_selection = true
    And prefer_server = "u1"

  Scenario: Default server omits prefer_server
    Given developer mode is on and "Default" is selected
    When a test request is built
    Then it carries user_server_selection = true
    And prefer_server is omitted

  Scenario: Outside developer mode no selection fields are sent
    Given developer mode is off
    When a test request is built
    Then neither user_server_selection nor prefer_server is present

  # --- List freshness -----------------------------------------------------

  Scenario: A selection no longer offered falls back to Default
    Given a server "u1" is selected
    When a /settings fetch returns a server list without "u1"
    Then the selection resets to Default

  Scenario: Changing the control server resets the selection and reloads the list
    Given a server is selected against control server A
    When the active control server changes to B
    Then the selection resets to Default
    And the server list is reloaded from B
    And the start screen "Server:" label and Settings row refresh immediately
```

## Notes

- Server list persisted in `RMBTSettings.availableTestServers`; the chosen uuid in
  `selectedTestServerUUID` (nil = default). `serverListControlUrl` records which control
  server the list belongs to, so a control-server change resets the selection
  (`resetTestServerSelectionIfControlServerChanged(to:)`) and the list is refetched.
- Clearing a nil-able setting must remove the key — `NSUserDefaults.set(NSNull())` aborts
  (CFPrefs). `RMBTSettings.observeValue` detects `NSNull` and calls `removeDataFor`.
- UI refresh after an async change (settings is a sheet, so the presenter's viewWillAppear
  doesn't fire) is driven by `.RMBTTestServerSelectionChanged`.
- The list screen is `RMBTServerSelectionViewController`; the start-screen label lives on
  `RMBTIntroPortraitView` (`server_label` = "Server: %@").

## References
- Sources/RMBTSettings.swift (`selectedTestServerUUID`, `availableTestServers`, `serverListControlUrl`, `resetTestServerSelectionIfControlServerChanged`, `observeValue`)
- Sources/RMBTServerSelectionViewController.swift
- Sources/RMBTSettingsViewController.swift ("Server selection" entry row)
- Sources/RMBTControlServer.swift (server list from /settings, control-server-change reset, notification)
- Sources/RMBTIntroViewController.swift / Sources/Views/RMBTIntroPortraitView.swift (start-screen "Server:" label)
- Sources/Requests/Requests.swift (`user_server_selection`, `prefer_server`)
- Sources/RMBTTestRunner.swift (sets the fields in developer mode)
- RMBTTests/ServerSelectionTests.swift
```
