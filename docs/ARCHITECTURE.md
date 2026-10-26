# Architecture

PashtoApp will teach Pashto from scratch. This document describes the skeleton that exists today and the boundaries later work has to respect. It is not a design for lessons, quizzes, or audio.

## Pieces

```
PashtoApp (iOS, SwiftUI)
    depends on
PashtoCore (Swift package, no Apple-only frameworks)
```

### PashtoApp

The iOS application target. Minimum deployment target is iOS 17. The bundle identifier is `com.mangallabs.pashto`. It uses the SwiftUI app lifecycle (`@main` `App`), an asset catalog, an `Info.plist`, a privacy manifest that declares no tracking and no collected data, and one string catalog.

The root view is a placeholder. It does not navigate, load content, or play sound.

UI copy is English. Strings live in `PashtoApp/Localizable.xcstrings` so another UI language can be added later by extending the catalog, without a second localization system. The development language is English.

Pashto content is not in the app yet. When it is added, each Pashto text block is right-to-left on its own. The surrounding English UI stays left-to-right. That layout is not implemented.

### PashtoCore

A library package at `Packages/PashtoCore`. It imports nothing from SwiftUI, SwiftData, UIKit, AVFoundation, or any other Apple-only framework. Foundation is available on Linux if a future type needs it; the skeleton does not use it.

`swift test` for this package is the logic test gate, and it runs on Linux. The iOS target is a thin shell over this package. Future lesson, quiz, and scheduling code belongs here once it is approved, so it can be tested without a simulator.

The package currently exposes a module name constant so the app target's dependency is real. It has no domain types.

## Data, accounts, and audio

These are constraints on later work, not code in this revision.

- **No backend and no accounts for the MVP.** Nothing in the skeleton talks to a server or identifies a user. If progress is stored later, it stays on device until a new decision says otherwise.
- **Pronunciation audio will be bundled in the app.** Apple has deprecated On-Demand Resources, so ODR is not the delivery plan. No audio files, player, or download step exist yet.

## Build and test

| What | Where it runs | Status |
| --- | --- | --- |
| `swift test` for `PashtoCore` | GitHub Actions, `ubuntu-24.04`, Swift 6.2.4 | In this repository |
| App compile, archive, TestFlight | Xcode Cloud, committed `PashtoApp.xcodeproj`, scheme `PashtoApp` | Workflow is created in App Store Connect, not in git |
| macOS GitHub Actions `xcodebuild` | Not added | Fallback only, needs owner approval |

`project.yml` is the file to edit. `PashtoApp.xcodeproj` is generated with XcodeGen 2.46.0 and committed so Xcode Cloud can see the project and the shared scheme without installing a generator. Details and the reason are in [decisions/0001-project-structure.md](decisions/0001-project-structure.md).

## Out of scope for this revision

- Modules, curriculum, or Pashto text
- Quiz, spaced-repetition, or streak logic
- Audio playback or a pronunciation button
- Screens other than the placeholder
- Accounts, sync, or a service
- An iOS test target, a macOS CI job, or an Xcode Cloud workflow file
