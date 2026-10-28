# 0002. Content format and the core boundary

- Date: 2026-10-27
- Status: Accepted

## Context

PashtoApp will ship offline lessons: words and phrases, five text quiz types, an alphabet section, and review. v1.0 has no audio playback. Audio has to be addable later by filling in content, without a new model.

`PashtoCore` is the Swift package the app links. It has no Apple-only dependencies, and `swift test` runs on Linux. The app target is still a SwiftUI shell. Lesson text, quizzes, and scheduling are not in the app.

Someone has to be able to write a unit, give every word a stable id, and have the app and the quizzes agree on that id later. The format, the id rules, what a release build is allowed to contain, and what stays out of `PashtoCore` are decided here. `ContentValidator` checks a decoded bundle against those rules. Merging source files, the release gate, and generating quizzes are later changes. They implement this decision; they do not reopen it.

## Decision

### The file the core reads

`PashtoCore` decodes one generated bundle, `content.json`. It does not read the source files and it does not touch the filesystem.

Authors write one JSON file per unit at `content/units/<unit-id>.json`. The file name is the unit id. Unit order lives in `content/course.json`, not in directory order. `content/difficult-characters.json` is the only copy of the difficult-character list. `content/release-units.json` lists the units in a release. `content/id-registry.json` lists every id that has ever shipped, including retired ids.

A content tool merges those into `content.json`. That file is committed. Nobody edits it by hand. CI regenerates it and fails if the diff is not empty. The same inputs produce the same bytes. The app and the validator read the difficult-character list from the bundle, not from the source file.

This package models the bundle. It does not model the source files or the tool.

The bundle shape:

| Field | Role |
| --- | --- |
| `schemaVersion` | Integer. This build reads `1` and rejects any other value. |
| `contentVersion` | Version string of the content, stored on progress later. |
| `variant` | String. v1.0 content is `af-kabul` (Kabul Pashto). |
| `romanization` | `table`, `difficultCharacters`, `unstressedWords`. |
| `items` | Every word, phrase, dialog line, and letter, each once. |
| `units` | Ordered course units. Order comes from `course.json` when the file is generated. |
| `nonDistractorGroups` | Groups of item ids that must not be offered as each other's wrong answers. |

A romanization table row is `letter`, `translit`, `ascii`, `pronunciation`, `description`. `difficultCharacters` is the character list (ټ ډ ړ ڼ ښ ږ څ ځ خ غ ژ ق ع). `unstressedWords` is the transliteration exception list, including `še`.

### One item, one id

Each word or phrase is one `ContentItem` with one id, defined in the unit where it is introduced. A lesson does not copy the item. It references it.

`LessonItemRef` is `item`, `role`, and an optional `sound`:

- `introduce` is the lesson where the item is learned. That reference is what later creates a review card. An item is introduced in exactly one ordinary lesson. A letter is introduced by appearing in that lesson's `letters` array.
- `soundExample` is only in the first unit of the bundle. Once `course.json` order is applied, that unit is the sounds unit. The item is shown as an example of a sound (`sound` is the transliteration letter, such as `ṭ`, and it is required). It does not create a review card. The same item must be introduced in exactly one regular lesson in a later unit. That `introduce` is what creates the card. An `introduce` in the sounds unit does not count.

`CourseUnit` is `id`, `track`, `title`, `lessons`. `track` is a string. The sample uses `main`.

`Lesson` is `id`, `title`, `items`, `letters`, and `dialogs`. `letters` lists letter items taught in that lesson. Omitted `letters` or `dialogs` decode as empty arrays. `Dialog` is `id` plus `turns` of `speaker` and `item`.

`ContentItem.kind` is `word`, `phrase`, `dialogLine`, or `letter`.

Fields on every item:

| Field | Meaning |
| --- | --- |
| `pashto`, `translit`, `pronunciation`, `en` | Pashto in Afghan orthography, scholarly transliteration, the simple pronunciation shown in the app, and the English meaning. `en` decodes as optional: null and a missing key are both nil. The validator requires a non-empty `en` for every kind. |
| `enAlt` | Optional further accepted English answers. |
| `usage` | Optional short English context shown in a quiz. |
| `pronunciationNote` | Optional English note. The validator requires it when `pashto` contains a character from `romanization.difficultCharacters`. Empty or whitespace-only counts as missing. |
| `responseTo` | Optional item id of the line this one answers. |
| `tokens`, `acceptedOrders` | Optional word-order data. `tokens` are explicit; the core does not split `pashto` on spaces. |
| `name`, `forms`, `sound` | Letter data. `forms` is `isolated`, `initial`, `medial`, `final`. |
| `audio` | Optional. Absent in v1.0 content. |
| `verification` | `status`, `checkedBy`, `checkedOn`, `comment`. |

`variant` is a bundle field. Items do not repeat it.

Which fields are required for which `kind` is a validator rule. The decoder accepts a letter without `forms` and a word with letter fields present, so the validator can report those as content errors.

### IDs

Ids match `^[uled]-[a-z0-9]+(-[a-z0-9]+)*$`. Each type also requires its own prefix, so an item id is `^e-[a-z0-9]+(-[a-z0-9]+)*$` and the other types use `u-`, `l-`, or `d-` the same way:

| Type | Prefix | Example |
| --- | --- | --- |
| `UnitID` | `u-` | `u-greetings` |
| `LessonID` | `l-` | `l-greetings-1` |
| `ItemID` | `e-` | `e-assalamu-alaykum` |
| `DialogID` | `d-` | `d-greetings-1` |

The body after the prefix is non-empty and has no leading, trailing, or doubled hyphen. `e-a` and `e-assalamu-alaykum` are ids. `e-`, `e--`, `e-x-`, and `e-a--b` are not. The id types reject anything else at decode time. There is one id pattern. Older sketch ids such as `u1-hilsen-03` are not valid.

An id is chosen from the transliteration when the item is created. It never changes because a spelling is fixed. A changed meaning is a new id. The old id is retired in `content/id-registry.json`. `retired` is not a verification status and not a field on `ContentItem`.

Uniqueness, "this registry id is missing", "this retired id came back", and "the same Pashto plus the same English and usage" are validator and tool rules. They are not decode rules.

### Verification and audio

`Verification.status` is `draft`, `check`, or `verified`. `checkedBy` and `checkedOn` are optional strings. `checkedOn` stays a string so the core does not parse a date. `verified` requiring a non-empty `checkedBy` and a valid ISO-8601 `checkedOn` is a validator rule. A draft file still decodes.

`AudioRef` is `normal`, `slow`, and `speaker`, each a non-empty string. `audio: null` and a missing `audio` key mean there is no audio. `audio: {}`, a missing part, a blank part, or an extra key fails decoding. `ContentItem.hasAudio` is true only when an `AudioRef` is present, which means the block is complete.

v1.0 content leaves `audio` null. The field is in the model so a later version can fill it in.

### Release filter

A release (TestFlight or App Store) does not drop `draft` or `check` items. The release step fails if any item in a unit listed in `content/release-units.json` is not `verified`, if a `verified` item is missing `checkedBy` or `checkedOn`, if a lesson is below the size rule, or if a reference breaks. Every item in a listed unit ships. A unit that is not listed is not part of that release.

The release step writes `content.release.json` and the Release app bundle contains that file. Debug contains the full `content.json`. `ContentFilter`, which hides `draft` and `check`, is for Debug and local builds only. The audio sample used by QA lives in a Debug-only file and is not in the release bundle.

The running app does not reject content in front of the user. A bad release fails CI before it ships.

Lesson size, enforced by that same release step: a lesson that introduces fewer than 4 items fails the job. 4 or 5 items is a warning. The target is 6 to 8.

### Decoding

Unknown keys are a decoding error at every object in the bundle, including nested ones. A typo such as `pronounciationNote` does not decode as "no pronunciation note". Null and a missing key are the same for optional fields.

The public way to read a bundle is `JSONDecoder` decoding `ContentBundle`. No custom decoder type is required.

### Normalization

`Normalization` is the only place that folds text for comparison and search.

- `nfc` and `isNFC` use Unicode scalars. Swift treats canonically equivalent strings as equal, so `==` cannot tell NFC from NFD.
- `comparisonKey` is NFC followed by locale-independent lowercase. It does not strip diacritics. English and `usage` use this. Pashto duplicate checks use `nfc` on `pashto`.
- `transliterationKey` decomposes to NFD, deletes only U+0301 (combining acute), recomposes to NFC, then lowercases the same way. Precomposed vowels such as `á` lose their accent. `ǧ`, `ṭ`, `x̌`, macrons, and carons stay. Search can ignore stress marks without collapsing those letters.
- `unicodeScalars` and `stressScalar` are the inputs for vowel and stress checks. `PashtoStressRule` performs those checks. `ContentValidator.validate(_:mode:)` uses that rule. A caller can pass a different `StressRule`.

Lowercasing uses `lowercased(with: nil)`. It does not use `Locale.current`.

### Boundary with the app

SwiftData, SwiftUI, `Bundle`, and file access stay in `PashtoApp`. The core takes `Data` it is given. Later scheduling will take an injected date provider and an injected `Calendar`. The core does not read the clock or the user's locale.

`PashtoCore` does not import UIKit, SwiftUI, or SwiftData.

### Linux guard

CI and `swift test` fail if any Swift file in `Packages/PashtoCore`, other than tests, imports UIKit, SwiftUI, or SwiftData, or reads the process clock or the current locale. The scan catches `Date()` and `Date.now`, `timeIntervalSinceNow`, `.current` and `.autoupdatingCurrent` on `Calendar`, `TimeZone`, `Locale`, and the `NSCalendar`, `NSTimeZone`, and `NSLocale` forms, every current or local `NSTimeZone` name (`local`, `system`, `default`, `localTimeZone`, `systemTimeZone`, `defaultTimeZone`), plus `NSLocale.currentLocale` and `NSCalendar.currentCalendar`. A fixed instant such as `Date(timeIntervalSince1970:)` and an injected calendar stay allowed.

## Consequences

- The app still does not load or display a course. Types, decoding, and bundle validation are in the package. `Tools/PashtoContentTool` merges the source files into `content/content.json` and runs the release gate. `ContentValidator.validate(_:mode:)` still runs the same bundle checks in both modes. The tool adds release-unit membership, lesson size, the v1.0 audio warning, and the missing-sound-example check. That sound check warns in dev. It errors in release only when `u-sounds` is listed in `release-units.json`. An empty release list is allowed. A non-empty list that omits `u-sounds` is an error. Lesson size counts `introduce` refs and letters. A `soundExample` does not count. The generated romanization table is empty until Pashto Expert supplies it. A missing table is a warning in dev and an error in release.
- A content typo in a key fails at decode time, before a quiz can ignore the field.
- Id typos fail at decode time. Duplicate ids, duplicate Pashto plus English and usage, and broken references are validator errors. Registry membership ("this id is missing", "this retired id came back") stays with the content tool, because the bundle does not carry the registry.
- `hasAudio` cannot be true for a partial block, because a partial block never becomes a value.
- `content/id-registry.json` starts empty. Nothing has shipped, so no id is registered and no id is retired. CI fails when a registered id is missing without `retired`, or when a retired id is used again.
- `content/release-units.json` starts empty. No unit is listed yet. An empty list does not require `u-sounds`. A non-empty list does. Dev mode still warns when a difficult character has no `soundExample`.
- `ContentFilter.devBuild` hides `draft` and `check` items. That is the only requirement a dev build skips. A `responseTo` that pointed at a hidden item stays, and a lesson that loses every item stays. Validation reports both as errors in every mode. Debug and dev builds are the only callers. A release build keeps every item and fails the gate instead.
- A warning when v1.0 content includes audio is part of the release gate. The app target does not embed `content.json` yet, so a macOS check of the Release app bundle is still waiting on that.
- Letter `forms` may use tatweel (U+0640) as the joining mark, as in `ـځـ` and `ـا`. The same character is an error in `pashto` and in every other text field. Digits in Pashto text stay an error until a numbers unit is agreed.
- The Linux guard is a text scan. It catches the calls named above. It does not prove the package is free of every Apple API.
