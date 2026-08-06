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
- Build (simulator default): `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build`
- Clean build: `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT clean`
- Unit tests: `xcodebuild -workspace RMBT.xcworkspace -scheme RMBT -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -parallel-testing-enabled NO test`
- Always use `OS=latest` rather than pinning a version — the installed runtime moves (it was 26.1, now 26.5) and a stale
  pin fails with a confusing "ineligible destination" list.
- Focused tests: append `-only-testing:RMBTTests/<TestClass>` (Swift Testing suites: `-only-testing:RMBTTests/<SuiteType>`)
- **Always pass `-parallel-testing-enabled NO`.** XCTest's parallel testing clones the destination simulator once per
  worker into `~/Library/Developer/XCTestDevices` and never deletes the clones — on another project 79 unattended runs
  left 283 GB and 2.79 M files behind. This suite mixes XCTest and Swift Testing, and Swift Testing already runs test
  functions concurrently *in-process*; the whole `RMBTTests` suite finishes in a few seconds, so clone + boot time
  dwarfs any gain. Never re-enable it to "make tests faster".
- Stale clones are invisible to `simctl list devices` — they live in a separate device set. Inspect with
  `xcrun simctl --set ~/Library/Developer/XCTestDevices list devices`; sweep with
  `pgrep -f "xcodebuild.*test" >/dev/null || xcrun simctl --set ~/Library/Developer/XCTestDevices delete all`.
  **The `pgrep` guard is mandatory** — an unguarded sweep deletes the live clones of a test run in another session or
  another project.
- CocoaPods (bundled): `bundle install` → `bundle exec pod install --repo-update`
- Pretty build logs: pipe any `xcodebuild` invocation to `| bundle exec xcpretty`. **Caution:** `xcpretty` does not
  understand Swift Testing and silently reports `Executed 0 tests` for suites written with it. Check the raw
  `xcodebuild` output (grep for `✘` / `Test run with`) to confirm test results.
- Reset pods only if needed: `bundle exec pod deintegrate && bundle exec pod install`

## Architecture & Patterns
- **Legacy UIKit surface**: MVC controllers with delegate callbacks; stateful singletons (`RMBTConfig`, `RMBTSettings`) coordinate shared data.
- **SwiftUI Network Coverage**: Modern view-model layering, heavy reliance on dependency injection and async sequences.
- **Measurement engine**: `RMBTTestRunner` orchestrates parallel `RMBTTestWorker`s for ping/download/upload; QoS suite covers TCP, UDP, DNS, HTTP checks.
- **Data flow**: Test run → progress callbacks → local persistence → submission via `RMBTControlServer` → history rendering in `RMBTHistoryIndexViewController`.
- **Localization**: string tables under `Resources/<lang>.lproj/Localizable.strings`. Active locales: `en`, `Base`, `de`, `ar`, `cs`, `es`, `fr`, `hr`, `hu` (kept in sync with the Xcode project's `knownRegions`). See the **Localization workflow** section below before adding or changing strings.

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

## Localization workflow
Translations are maintained by humans and are intentionally behind. When you add or change user-facing copy, follow this workflow so nothing ships as a raw key and translators have a clear backlog.

- **Never auto-translate / machine-translate.** Only provide real values for the source language (English). All other locales get an English placeholder until a human translates them.
- **New user-facing strings** go into `Base` and `en` with the real English value (these are the source of truth).
- **All other locales** (`de`, `ar`, `cs`, `es`, `fr`, `hr`, `hu`) get the same key with the **English text as a placeholder**, appended under the per-file comment block:
  `/* ===== TODO: NEEDS TRANSLATION (English placeholder) ===== */`
  Keep these entries grouped under that header so the translation backlog is easy to find. German is included here too — do not translate it inline unless explicitly asked.
- **iOS fallback reality**: there is no per-key fallback to English. A locale missing a key renders the **key string itself**, so every active locale must contain every key (English placeholder is acceptable). Run a key-parity check across locales after edits.
- **SwiftUI**: `Text("literal")`, `LabeledContent("literal")`, `.navigationTitle("literal")`, `Toggle("literal", …)`, etc. take a `LocalizedStringKey` — the literal *is* the lookup key, so registering that literal in the `.strings` files localizes it with no code change. Prefer this over inventing identifier keys for SwiftUI views. (`Text(someStringVariable)` is NOT localized.)
- **Adding a new locale**: drop `Resources/<lang>.lproj/Localizable.strings`, then add `<lang>` to the Xcode project's `knownRegions` AND to the `Localizable.strings` variant group (use the `xcodeproj` gem; do not hand-edit `project.pbxproj`). Verify with a build that `<lang>.lproj` is bundled into the `.app`.
- **Validate**: run `plutil -lint` on every changed `.strings` file and check for duplicate keys before finishing.

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
- Use `bundle exec xcpretty` when running `xcodebuild` tests locally to keep logs readable, but read Swift Testing
  results from the raw output — see the caution under **Commands**.
- Run the suite with the exact command under **Commands**, including `-parallel-testing-enabled NO`. A test that passes
  in isolation but fails in the full suite is usually a `TestClock` race, not a real regression — the whole suite runs
  in a few seconds, so re-run it a few times before believing either result.

## Environment
- Use Homebrew Ruby ≥ 3.1; update PATH via `eval "$(/opt/homebrew/bin/brew shellenv)"` then prepend `/opt/homebrew/opt/ruby/bin`.
- CocoaPods must run through Bundler to match the pinned version in `Gemfile.lock`. Run `bundle install` once after a fresh clone; gems land in `./vendor/bundle` (per `.bundle/config`).
- Xcode 26+, iOS deployment target 17.0+. Simulator defaults to iPhone 17 Pro at `OS=latest` (visionOS style naming by Apple).

### Fresh-clone setup
A clean clone builds with no private access — `Scripts/update_configurations_from_private.sh` falls back to `public/Configurations/` whenever the `private/` submodule is absent or empty. **Clone without `--recursive`** unless you have access to `open-rmbt-ios-private`, otherwise the clone exits non-zero on a submodule SSH failure (the main worktree is still usable).

The script is an unconditional `cp` on every build — there is no "write once" guard, and the `Update Configurations` build phase declares no outputs, so it always runs. It uses `cp -a` for `Configs/`, which preserves source mtimes and therefore does *not* trigger needless recompiles. Running the script by hand is exactly what the build phase does; it is idempotent and safe.

Generated destinations — never edit these, edit `private/` or `public/` instead:
- `Configs/RMBTConfig.swift` — untracked (`.gitignore`).
- `Resources/Images.xcassets/AppIcon.appiconset/` — untracked (`.gitignore`).
- `Resources/RMBT-Info.plist` — **tracked**. Regenerated every build, so it appears as a local modification whenever the active config differs from the committed content. The private version sets the `RTR-NetTest` display name, `rmbtat` URL scheme, `NSLocalNetworkUsageDescription` (DNS QoS test) and `UIBackgroundModes: location` (coverage measurements). **Do not commit it from a public-config build** — that silently strips RTR branding and background location. Revert with `git checkout -- Resources/RMBT-Info.plist`.

Order matters, and both steps have failure modes that look unrelated to their real cause:
1. `bundle install` — **must** run on Ruby ≥ 3.1. On macOS system Ruby 2.6 it fails with `Could not find 'bundler' (2.7.2) required by your Gemfile.lock`, because `Gemfile.lock` pins `BUNDLED WITH 2.7.2`. The error names bundler, not Ruby, and following its `gem install bundler:2.7.2` advice also fails. Fix the Ruby, not the bundler.
2. `bundle exec pod install --repo-update` — always via `bundle exec`. A stray global `pod` (Homebrew's or an old `/usr/local/bin/pod`) resolves a different `xcodeproj` and reintroduces the `objectVersion` failure below.
3. `./Scripts/update_configurations_from_private.sh` — run it manually once. The same script runs as a build phase, but Xcode resolves compiler input files *before* build phases execute, so the first build of a fresh clone fails with `Build input file cannot be found: '.../Configs/RMBTConfig.swift'`. Building a second time also works, since the phase has by then created the file.

Then open `RMBT.xcworkspace`, never `RMBT.xcodeproj`. Without `Pods/` the build fails on missing `Pods-RMBT.*.xcconfig`, missing xcfilelists, or `The sandbox is not in sync with the Podfile.lock`.

### Known issues / workarounds
- **`pod install` fails with `Unable to find compatibility version string for object version 71`**: Xcode 16.2+ writes `objectVersion = 71`, which `xcodeproj` 1.27.0 does not recognise — Apple's numbering is not monotonic (16.0 = 77, 16.2 = 71), so this is an *unknown* value rather than one above a cap. **Fixed** by pinning `xcodeproj 1.28.1` in `Gemfile.lock`, which knows 70, 71 and 100; run `bundle install` to pick it up. Do not hand-edit `objectVersion` to 77 any more — that old workaround churned `project.pbxproj` on every Xcode save. Tracked upstream as CocoaPods #12805 / #12840.
- **Do not downgrade `xcodeproj` below 1.28.1**, and if a future Xcode writes an `objectVersion` the gem does not know (Xcode 26.3 already writes 100), bump the gem rather than editing the project file.
- **App Store upload fails with ITMS-90085 "No architectures in the binary"**: caused by header-only Pods (e.g. `libextobjc/EXTKeyPathCoding`) producing an empty `.framework` wrapper that Xcode 26+ no longer fills with a stub binary. Symptoms: framework folder in the IPA contains `_CodeSignature/` and `Info.plist` but no executable. Fix: drop the Pod from `Podfile` and remove the corresponding `import` (verify with `lipo -archs` on every Mach-O inside the .ipa).

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
