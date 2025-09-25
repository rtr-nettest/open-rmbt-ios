# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open-RMBT iOS App is a network speed testing application developed for the Austrian Regulatory Authority for Broadcasting and Telecommunications (RTR). It performs multi-threaded bandwidth measurements, QoS testing, and network coverage analysis.

## Build Commands

### Development Build
```bash
# Build for iPhone 16 simulator (default)
xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 16' build

# Clean build
xcodebuild -workspace RMBT.xcworkspace -scheme RMBT clean
```

### Testing
```bash
# Run unit tests
xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run specific test class
xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:RMBTTests/NetworkCoverageViewModelTests
```

### Dependency Management
```bash
# Install/update CocoaPods dependencies
pod install

# Update pods to latest versions
pod update
```

**Toolchain Setup (Ruby + CocoaPods)**
- Prefer Homebrew Ruby (>= 3.1). The macOS system Ruby 2.6 is too old for modern CocoaPods.
- Add Homebrew to your shell and prefer its Ruby first on PATH:
  - `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile`
  - `eval "$(/opt/homebrew/bin/brew shellenv)"`
  - `export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"`
- Install Ruby and CocoaPods if needed:
  - `brew install ruby cocoapods`
- Install gems via Bundler (pinned in Gemfile):
  - `bundle install`
- Always run CocoaPods via Bundler to ensure the pinned version is used:
  - `bundle exec pod install --repo-update`
- If CocoaPods complains about `~/.netrc` permissions:
  - `chmod 600 ~/.netrc`

**Why Bundler**
- The Gemfile pins CocoaPods (>= 1.16) to match Xcode 16 project formats. Using `bundle exec` guarantees a consistent gem set across machines and CI.

**Xcode Project Format**
- The project uses `objectVersion = 77` (Xcode 16). Older CocoaPods/xcodeproj can error with: `Unable to find compatibility version string for object version '70'`. Use CocoaPods >= 1.16 (already enforced by Gemfile).

**First-Time Setup (Fresh Clone)**
- `git submodule update --init --recursive`
- `eval "$(/opt/homebrew/bin/brew shellenv)" && export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"`
- `bundle install`
- `bundle exec pod install --repo-update`
- Open `RMBT.xcworkspace` (not the `.xcodeproj`).

**Build From CLI**
- Dev simulator build:
  - `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build`
- Pretty output:
  - `xcodebuild … | bundle exec xcpretty`

**Configuration System Reminder**
- Private/public configuration files are copied by `Scripts/update_configurations_from_private.sh` at build time.
- Keep new constants in sync across public and private configs (e.g., `ACTIVATE_COVERAGE_FEATURE_CODE`, `DEACTIVATE_COVERAGE_FEATURE_CODE`) to avoid compile errors.

**Common Troubleshooting**
- `bundler` version error or system Ruby 2.6 on PATH:
  - `eval "$(/opt/homebrew/bin/brew shellenv)" && export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"`
  - Re-run: `bundle install` then `bundle exec pod install --repo-update`
- CDN repo error about `~/.netrc` permissions → `chmod 600 ~/.netrc`
- Missing Target Support Files → `bundle exec pod deintegrate && bundle exec pod install`
- Clean build: `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT clean`

## Configuration System

The project uses a dual configuration system with `private/` and `public/` folders:

- Configuration files are copied from these folders during build via `Scripts/update_configurations_from_private.sh`
- Main configuration in `Configs/RMBTConfig.swift` contains server endpoints and API keys
- Build info is injected via `Scripts/add_build_infos.sh`

**Important**: Always configure server parameters in `RMBTConfig.swift` before building.

## Architecture Overview

### Core Components

**Network Testing Engine** (`Sources/Test/`, `Sources/RMBTTest*`)
- Multi-threaded speed measurements (upload/download/ping)
- QoS testing suite with various test types (TCP, UDP, DNS, HTTP, etc.)
- Loop mode for automated testing sequences
- Real-time progress tracking and result visualization

**Network Coverage** (`Sources/NetworkCoverage/`)
- Location-based network measurement system
- GPS fence management for automated testing
- Persistent data storage for coverage analysis
- UDP ping sequence testing

**Map Integration** (`Sources/Map/`)
- MapKit-based visualization of test results
- Overlay system for coverage data display
- Search and filtering capabilities
- Location-based result queries

**History Management** (`Sources/History/`)
- Test result storage and retrieval
- Export functionality (CSV, PDF, XLSX formats)
- Sync capabilities with server backend
- Detailed QoS result analysis

### Key Architectural Patterns

#### Legacy code architecture (UIKit)
- **MVC Architecture**: Traditional iOS pattern with UIKit
- **Delegate Pattern**: Extensive use for async operations and UI updates
- **Singleton Services**: `RMBTConfig`, `RMBTSettings` for global state
- **Protocol-Oriented Design**: Swift protocols for test interfaces and data models
- **Threading**: Background queues for network operations, main queue for UI updates

#### New code architecture (SwiftUI)
- The **Network Coverage** is written in new SwiftUI architecure, following View-Model pattern
- **Testability** is very important factor of this architecture. It is recommended to use TDD (Test Driven Development).
- For 

### Data Flow

1. **Test Initiation**: User starts test → `RMBTTestRunner` coordinates execution
2. **Measurement**: Multiple `RMBTTestWorker` instances perform parallel measurements
3. **Progress Updates**: Real-time UI updates via delegate callbacks
4. **Result Storage**: Local persistence + server submission via `RMBTControlServer`
5. **History Display**: Retrieval and presentation in `RMBTHistoryIndexViewController`

## Key Dependencies

- **Alamofire**: HTTP networking and server communication
- **CocoaAsyncSocket**: Low-level socket operations for speed tests
- **XCGLogger**: Comprehensive logging system
- **MaterialComponents**: UI components following Material Design
- **ObjectMapper**: JSON serialization for API responses
- **KeychainAccess**: Secure storage for user credentials

## Development Notes

### Minimum Requirements
- iOS 17.0+ deployment target
- Xcode 13+ for building
- CocoaPods for dependency management

### Localization
Supports English, German, and Croatian with localized strings in `Resources/*/Localizable.strings`

### Testing Infrastructure
- Unit tests in `RMBTTests/` covering core measurement logic
- Network coverage simulation tests
- QoS test validation suites

#### Unit Testing Best Practices
- It is advised to use TDD (Test Driven Development)
- Unit tests should follow strict rules to ensure they only test business logic, not concrete implementation.

See [Unit Testing Best Practices](./docs/unit-testing-best-practices.md)

### Network Protocols
- Custom SSL/TLS handling for secure measurements
- Multi-threaded TCP connections for bandwidth testing
- UDP implementations for ping and QoS measurements
- WebSocket connections for real-time server communication
