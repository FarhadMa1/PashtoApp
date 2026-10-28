# Architecture

PashtoApp will teach Pashto from scratch. This document describes the app shell, the content types in `PashtoCore`, and the boundaries later work has to respect. Quizzes, review scheduling, and audio playback are not in this revision.

## Pieces

```
PashtoApp (iOS, SwiftUI)
    depends on
PashtoCore (Swift package, no Apple-only frameworks)

Tools/PashtoContentTool
    depends on PashtoCore
    is not linked by the app
```

### PashtoApp

The iOS application target. Minimum deployment target is iOS 17. The bundle identifier is `com.mangallabs.pashto`. It uses the SwiftUI app lifecycle (`@main` `App`), an asset catalog, an `Info.plist`, a privacy manifest that declares no tracking and no collected data, and one string catalog.

The root view is a placeholder. It does not navigate, load content, or play sound.

UI copy is English. Strings live in `PashtoApp/Localizable.xcstrings` so another UI language can be added later by extending the catalog, without a second localization system. The development language is English.

Pashto content is not in the app yet. When it is added, each Pashto text block is right-to-left on its own. The surrounding English UI stays left-to-right. That layout is not implemented.

### PashtoCore

A library package at `Packages/PashtoCore`. It imports nothing from SwiftUI, SwiftData, UIKit, or any other Apple-only framework. Foundation is used for JSON decoding and Unicode normalization, and that Foundation is the open-source one `swift test` uses on Linux.

`swift test` for this package is the logic test gate, and it runs on Linux. The iOS target is a thin shell over this package. Quiz and scheduling code belongs here once it is added, so it can be tested without a simulator.

The package exposes:

- Content value types for the generated `content.json` bundle (`ContentBundle`, `ContentItem`, `CourseUnit`, `Lesson`, `LessonItemRef`, and the id types). The format, id rules, release filter, and the boundary with the app are in [decisions/0002-content-format.md](decisions/0002-content-format.md).
- `Normalization`, the only place that folds text for comparison.
- `ContentValidator`, which checks a decoded bundle and returns every issue it finds. Both modes run the same checks.
- `ContentFilter.devBuild`, which hides `draft` and `check` items for a Debug or dev build. A release build does not call it.
- `PashtoCore.moduleName`, so the app target's dependency stays linked.

The app does not load a course yet. SwiftData, SwiftUI, `Bundle`, and file access stay in the app. The core decodes `Data` it is given. It does not read the process clock or the current locale (`Date()` / `Date.now`, `timeIntervalSinceNow`, `.current` / `.autoupdatingCurrent`, or `NSTimeZone` local, system, and default). CI and `swift test` run `scripts/linux-guard.sh` against the package sources.

## Data, accounts, and audio

These are constraints on later work, not code in this revision.

- **No backend and no accounts for the MVP.** Nothing in the skeleton talks to a server or identifies a user. If progress is stored later, it stays on device until a new decision says otherwise.
- **Pronunciation audio will be bundled in the app.** Apple has deprecated On-Demand Resources, so ODR is not the delivery plan. No audio files, player, or download step exist yet.

## Build and test

| What | Where it runs | Status |
| --- | --- | --- |
| `swift test` for `PashtoCore` and `PashtoContentTool` | GitHub Actions, `ubuntu-24.04`, Swift 6.2.4 | In this repository |
| `pashto-content merge --check` and `validate --mode dev` | Linux job `swift test (Linux)` | In this repository |
| `validate --mode release` | Linux job `validate release` | Runs on every pull request and does not fail the workflow |
| App compile, archive, TestFlight | Xcode Cloud, committed `PashtoApp.xcodeproj`, scheme `PashtoApp` | Workflow is created in App Store Connect, not in git |
| macOS GitHub Actions check of the Release app bundle | Not added | The app target does not embed `content.json` yet |

`project.yml` is the file to edit. `PashtoApp.xcodeproj` is generated with XcodeGen 2.46.0 and committed so Xcode Cloud can see the project and the shared scheme without installing a generator. Details and the reason are in [decisions/0001-project-structure.md](decisions/0001-project-structure.md).

## Out of scope for this revision

- Loading the course inside the app, and a macOS check that the Release bundle contains only `release-units.json`
- Quiz, spaced-repetition, or streak logic
- Audio playback or a pronunciation button
- Screens other than the placeholder
- Accounts, sync, or a service
- An iOS test target, a macOS CI job, or an Xcode Cloud workflow file
