# Debug Mode Setup Guide

This guide explains how to enable debug mode in the Open-RMBT iOS app to access advanced developer features, including custom server configuration.

## Enabling Debug Mode

### Step 1: Access Settings
1. Launch the Open-RMBT app
2. Navigate to **Settings** (gear icon)

### Step 2: Activate Debug Mode
1. In the Settings screen, locate the **"Version"** row
2. Find the version information on the right side (e.g., "1.2.3(456) Debug (Jan 1 2024)")
3. **Tap 10 times rapidly** on the version number/build details area
4. A popup will appear asking for a "Dev Code"
5. Enter: `23656990`
6. Tap "Enter"

### Step 3: Access Debug Options
After entering the correct dev code:
- Debug sections will appear in the Settings screen
- Scroll down to find new debug options including:
  - **Debug Control Server Customization**
  - **Debug Logging Options**
  - **IPv6 Force Options**

## Changing Server URL

Once debug mode is enabled, you can change the server URL:

### Step 1: Enable Custom Control Server
1. Find the **"Debug Control Server Customization"** section
2. Toggle the switch to **ON**
3. Additional fields will appear below

### Step 2: Configure Custom Server
1. **Debug Control Server Hostname**: Enter your custom hostname (e.g., `dev2.netztest.at`)
2. **Debug Control Server Port**: Leave as default (80) or specify custom port
3. **Debug Control Server Use SSL**: Keep ON for HTTPS connections

### Example Configuration
- **Hostname**: `dev2.netztest.at`
- **Port**: `80` (default)
- **Use SSL**: `ON`

This will make the app connect to: `https://dev2.netztest.at/RMBTControlServer`

## Disabling Debug Mode

To disable debug mode:
1. Repeat the 10-tap procedure on the version number
2. Enter: `00000000` (eight zeros)
3. Debug options will be hidden and custom server settings will be ignored

## Technical Details

### Code References
- **UI Location**: `Sources/MainStoryboard.storyboard` (label ID: `geb-Fs-fpz`)
- **Tap Handler**: `Sources/RMBTSettingsViewController.swift:356-358`
- **Gesture Setup**: `Sources/RMBTSettingsViewController.swift:194-196`
- **Server Logic**: `Sources/RMBTControlServer.swift:updateWithCurrentSettings()`

### Dev Codes
- **Activate**: `23656990` (defined in `private/Configurations/Configs/RMBTConfig.swift`)
- **Deactivate**: `00000000`

### Settings Storage
Debug settings are stored in iOS UserDefaults and are not committed to the repository, making this approach git-safe for temporary configuration changes.

## Security Note

Debug mode provides access to advanced features intended for development and testing. Only enable debug mode when necessary and disable it when not in use.