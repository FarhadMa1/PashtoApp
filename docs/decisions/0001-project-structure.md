# 0001. Project structure

- Date: 2026-10-25
- Status: Accepted

## Context

PashtoApp needs an iOS shell and a place for future lesson and quiz logic. The only approved work right now is that skeleton. There is no Mac in the current development environment. Day-to-day logic tests run on Linux. Compiles, the simulator, and TestFlight will run on Xcode Cloud. A GitHub Actions macOS runner is not used to archive the app. On 2026-11-02 Farhad approved one for the SwiftData package tests.

The Xcode project has to be reproducible without hand-editing `project.pbxproj` on a Mac. XcodeGen (`project.yml`) is the generator. On 2026-11-02 Farhad approved a GitHub Actions macOS runner for the SwiftData package tests. That job does not archive the app.

Two ways to feed that project to Xcode Cloud were considered:

1. Commit the generated `.xcodeproj`.
2. Gitignore it and generate it in `ci_scripts/ci_post_clone.sh` (`brew install xcodegen && xcodegen generate`).

## Decision

### Pure-Swift core, tested on Linux

`Packages/PashtoCore` is a Swift package with no Apple-only framework dependencies. The app target links it. Logic tests are `swift test` on that package. GitHub Actions runs them on `ubuntu-24.04` inside the official `swift:6.2.4-noble` image.

Farhad approved a macOS GitHub Actions job on 2026-11-02. It uses a standard GitHub-hosted `macos-15` runner and the latest stable Xcode on that image. For this public repository those runners are free. The job runs `swift test` for `Packages/PashtoPersistence` only, and only when that package, `Packages/PashtoCore/Sources/PashtoCore/Progress`, the shared contract in `PashtoCoreTesting`, or the workflow file changes. Linux does not build that package. A macOS `xcodebuild` of the iOS app is still not a GitHub Actions job. Xcode Cloud remains the archive path.

### Progress file

`Packages/PashtoPersistence` stores progress in SwiftData schema `SchemaV1` (version identifier 1.0.0). `ProgressMigrationPlan` lists that schema and has no stages yet.

`StreakRecord.freezeUsedDays` is the days a streak freeze was used. `StoreMetaRecord.contentVersion` is the content bundle the file was written with. After the first write, `load` returns that stored version and does not replace it. `StoreMetaRecord.snapshotVersion` is `ProgressSnapshot.currentVersion`, the shape of the whole snapshot. It is separate from the SwiftData schema version and from the active session's `payloadVersion`.

V1 may change freely until the first TestFlight build anyone installs. After that, a shipped `VersionedSchema` does not change. A later shape is a new `SchemaVn` and a stage on `ProgressMigrationPlan`. There is no checked-in V1 `.store` file yet. The macOS job will generate it, and that file is checked in before the first TestFlight build.

Days are stored as `Int` days since 1970-01-01. The number is `LocalDay.days(from:)` and is read back with `adding(days:)`. That is the same day number the core uses for the user's local calendar day. It is not the UTC date of an instant. The core counts civil dates with a Gregorian calendar fixed to UTC only so a 23-hour or 25-hour local day still counts as one day.

`load` deletes an active session whose payload version is older than this build, or whose JSON does not decode. It logs that drop and returns the rest of the file. A newer schema, a newer `snapshotVersion`, or a newer session payload still throws, and nothing is written over it.

### English-only UI, String Catalog

The development language is English. User-facing strings go in `PashtoApp/Localizable.xcstrings`. Additional UI languages are new localizations in that catalog, not a new mechanism. Pashto lesson text, later, is right-to-left per text block inside an otherwise English, left-to-right UI. No Pashto strings and no RTL layout are in this revision.

### No backend and no accounts for the MVP

The skeleton has no network client, account model, or service. MVP progress, if it is added later, stays on device until a new ADR says otherwise.

### Audio is bundled in the app

When pronunciation audio is approved, the files ship in the app bundle. On-Demand Resources are deprecated and are not the plan. This revision includes no audio assets and no playback code.

### Commit the generated Xcode project

`project.yml` is the only file people edit. `PashtoApp.xcodeproj` is generated with XcodeGen 2.46.0 and committed, including the shared `PashtoApp` scheme. There is no `ci_post_clone.sh`.

`ci_post_clone.sh` is a supported place to generate a project, and some apps do that. Committing the project is still the more robust setup for this repository:

- **The workflow can see a scheme immediately.** With the project in git, App Store Connect and Xcode can list `PashtoApp.xcodeproj` and the shared `PashtoApp` scheme. A repository that only generates the project during the build has nothing to select until that script has already succeeded.
- **Archive does not depend on Homebrew.** A post-clone script would `brew install xcodegen` on every build. Formula, bottle, and network failures are a common source of red Xcode Cloud builds, on a step this app does not need once the project is in git.
- **The archived project is the reviewed project.** Generating during clone follows whatever XcodeGen version Homebrew resolves that day. The committed project is the one in the pull request. `project.yml` pins `minimumXcodeGenVersion` to 2.46.0.
- **The macOS fallback stays a plain `xcodebuild`.** When a macOS GitHub Actions job is approved, it can build `PashtoApp.xcodeproj` directly, with no generator install.

The cost is noisier diffs in `project.pbxproj`, and a discipline rule: any `project.yml` change is committed together with a regenerated project. That cost is small while there is one application target and one local package. Revisit generation-in-CI only if project-file conflicts become a real problem and the Homebrew dependency is an accepted trade.

`PashtoApp.xcodeproj` was generated on Linux from `project.yml` with XcodeGen 2.46.0. The unmodified binary crashes on the Swift 6.2.4 Linux toolchain inside `Bundle(for:)` while searching for setting presets. Generation finished after that lookup was skipped; the presets loaded were the 2.46.0 files, a second run produced the same `project.pbxproj`, and the local-package product entry matches XcodeGen's own fixture (product name, no remote package pointer). That check shows the spec is valid. It does not show that the iOS target compiles. There was no Mac and no Xcode here. Regenerate on a Mac.

### Other skeleton defaults

- iOS 17 minimum, Swift 6 language mode (`SWIFT_VERSION` 6.0), Swift tools version 6.0 in the package.
- iPhone only, portrait.
- Bundle id `com.mangallabs.pashto` is final. It was chosen to match the owner's future company, Mangal Labs.
- No development team in the project. Signing team comes from Xcode Cloud or a local Xcode account.
- `ITSAppUsesNonExemptEncryption` is false so export compliance is not re-asked on every upload. The app uses no custom encryption.
- App category is education. The display name is Pashto.
- The app icon is a flat placeholder image so the catalog has the required 1024 slot. Replace it before shipping.
- `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and no required-reason API access. Update it when the app starts using those APIs.
- Version is 0.1.0 (build 1).

## Consequences

- Linux can prove the core package tests pass. It cannot prove the app builds, signs, or launches, and it does not build `PashtoPersistence`.
- The macOS job proves the SwiftData package tests pass. It does not prove the app archives.
- Xcode Cloud setup is a product-and-scheme selection against a project that is already in the repository. No custom CI script has to stay in sync with `project.yml`.
- Forgetting to regenerate after a spec edit leaves CI building the old project. Reviewers should treat a `project.yml` change without an `.xcodeproj` change as incomplete.
- Feature work (content, quizzes, audio, extra screens, accounts) is a new approval, not a follow-on implied by this ADR.
