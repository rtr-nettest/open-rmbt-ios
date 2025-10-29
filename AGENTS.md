# Agent Guide

## Purpose
Agents act as senior Swift collaborators. Keep responses concise,
clarify uncertainty before coding, and align suggestions with the rules linked below.
Explain clearly your reasoning behind your decisions and pros/cons of chosen solution.

## Rule Index
- `@ai-rules/rule-loading.md` — always load this first; it selects the right rule pack for the task.
- `@ai-rules/general.md` — baseline rules for Swift, UIKit, and SwiftUI work in this codebase.
- `@ai-rules/testing.md` — testing-specific rules distilled from our TDD playbook. Required when touching tests or test fixtures.
- Deep dives live under `@docs/`, you can read it if you need longer-form architectural or product context.

## Repository Overview
- **Product**: Open-RMBT iOS — RTR’s network measurement client (speed tests, QoS, coverage).
- **Key modules**: `Sources/Test/` (measurement engine), `Sources/NetworkCoverage/` (SwiftUI coverage UI), `Sources/Map/`, `Sources/History/`.
- **Configuration**: Public/private configs synced by `Scripts/update_configurations_from_private.sh`. Update both sides when adding constants.
- **Docs**: Deep product and architecture context: in @docs/sdd/ folder. Business logic user stories in @docs/user-stories/ folder. Update these folders whenever appropriate to reflect up-to-date logic.
- **Private data**: Secrets and branded assets live under `private/`; never commit them publicly.

## Commands
- Build (simulator default): `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
- Clean build: `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT clean`
- Unit tests: `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
- Focused tests: append `-only-testing:RMBTTests/<TestClass>`
- CocoaPods (bundled): `bundle install` → `bundle exec pod install --repo-update`
- Pretty build logs: pipe any `xcodebuild` invocation to `| bundle exec xcpretty`
- Reset pods only if needed: `bundle exec pod deintegrate && bundle exec pod install`

## Architecture & Patterns
- **Legacy UIKit surface**: MVC controllers with delegate callbacks; stateful singletons (`RMBTConfig`, `RMBTSettings`) coordinate shared data.
- **SwiftUI Network Coverage**: Modern view-model layering, heavy reliance on dependency injection and async sequences.
- **Measurement engine**: `RMBTTestRunner` orchestrates parallel `RMBTTestWorker`s for ping/download/upload; QoS suite covers TCP, UDP, DNS, HTTP checks.
- **Data flow**: Test run → progress callbacks → local persistence → submission via `RMBTControlServer` → history rendering in `RMBTHistoryIndexViewController`.
- **Localization**: English, German, Croatian string tables under `Resources/**/Localizable.strings`.

## Key Integration Points
- **RTR Control Backend** via `RMBTControlServer` (Alamofire-based). Keep endpoints synced in `Configs/RMBTConfig.swift`.
- **Socket stack**: `CocoaAsyncSocket` for raw TCP/UDP; respect threading guidance from `general` rule pack.
- **Logging**: `XCGLogger` configured globally; prefer structured logging categories to printf.
- **Map overlays**: MapKit annotations & overlays assembled in `Sources/Map/`; watch for performance when expanding datasets.
- **SwiftData** - Network Coverage feature uses SwiftData as a persistence layer. The logic is present inside `Sources/NetworkCoverage/Persistence` folder.
- **Scripts**: `Scripts/update_configurations_from_private.sh` copies private → public configs at build, `Scripts/add_build_infos.sh` injects metadata.

## Code Style
- Follow Swift API Design Guidelines: expressive names, argument labels that read naturally.
- Prefer dependency injection over singletons in new SwiftUI code; legacy controllers may still depend on `RMBTSettings`.
- Avoid force unwraps except in guarded test helpers; prefer `guard let` with logged failures.
- Keep public/private configs mirrored; add comments when temporary divergence is intentional.
- Update localization strings for any user-facing copy changes.

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services
- Do not commit code yourself
- When creating new file, never put your name as author of the file

## Testing
- Default to TDD: create or update tests under `RMBTTests/` before implementation changes.
- Use the WHEN_THEN test naming pattern and helper factories defined in the testing rule pack.
- Test only business behavior, not implementation details.
- Trigger `@ai-rules/testing.md` whenever you modify tests, fixtures, or concurrency-sensitive code paths.
- Unit tests should be aligned with user stories in `@docs/user-stories`. Uf you add new behavior into use stories, make sure also test are added. If you change test behavior, make sure relevant user stories are updated.
- Use `bundle exec xcpretty` when running `xcodebuild` tests locally to keep logs readable.

## Environment
- Use Homebrew Ruby ≥ 3.1; update PATH via `eval "$(/opt/homebrew/bin/brew shellenv)"` then prepend `/opt/homebrew/opt/ruby/bin`.
- CocoaPods must run through Bundler to match the pinned version in `Gemfile.lock`.
- Xcode 26+, iOS deployment target 17.0+. Simulator defaults to iPhone 17 Pro / iOS 26.0 (visionOS style naming by Apple).

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
