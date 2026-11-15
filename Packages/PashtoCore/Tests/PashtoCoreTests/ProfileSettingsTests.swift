import Foundation
import Testing
import PashtoCore

struct ProfileSettingsTests {
    @Test func settingsRoundTripAndIgnoreUnknownValues() {
        let suite = "pashto.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ProfileSettingsStore.load(from: defaults) == .initial)

        let saved = ProfileSettings(appearance: .dark, audioSpeed: .slower, textSizeOffset: 1)
        ProfileSettingsStore.save(saved, to: defaults)
        #expect(ProfileSettingsStore.load(from: defaults) == saved)

        defaults.set("nope", forKey: ProfileSettingsStore.appearanceKey)
        defaults.set("nope", forKey: ProfileSettingsStore.audioSpeedKey)
        defaults.set(9, forKey: ProfileSettingsStore.textSizeOffsetKey)
        let fallback = ProfileSettingsStore.load(from: defaults)
        #expect(fallback.appearance == .system)
        #expect(fallback.audioSpeed == .normal)
        #expect(fallback.textSizeOffset == TextSizeOffset.maximum)

        defaults.set(-4, forKey: ProfileSettingsStore.textSizeOffsetKey)
        #expect(ProfileSettingsStore.load(from: defaults).textSizeOffset == TextSizeOffset.minimum)
    }

    @Test func textSizeOffsetMovesAlongTheSystemLadder() {
        #expect(TextSizeOffset.shifted(.large, by: 0) == .large)
        #expect(TextSizeOffset.shifted(.large, by: 1) == .xLarge)
        #expect(TextSizeOffset.shifted(.large, by: -1) == .medium)
        #expect(TextSizeOffset.shifted(.accessibility5, by: 1) == .accessibility5)
        #expect(TextSizeOffset.shifted(.xSmall, by: -1) == .xSmall)
        #expect(TextSizeOffset.shifted(.xxxLarge, by: 4) == .accessibility1)
        #expect(TextSizeOffset.clamped(0) == 0)
        #expect(TextSizeStep.allCases.first == .xSmall)
        #expect(TextSizeStep.allCases.last == .accessibility5)
    }

    @Test func audioSpeedRatesStayOnTheThreeSteps() {
        #expect(AudioSpeed.slower.playbackRate == 0.75)
        #expect(AudioSpeed.normal.playbackRate == 1)
        #expect(AudioSpeed.faster.playbackRate == 1.25)
        #expect(AudioSpeed.resolved(nil) == .normal)
        #expect(AudioSpeed.resolved(AudioSpeed.faster.rawValue) == .faster)
    }

    @Test func cancelKeepsProgressAndResetClearsOnlyProgress() async throws {
        let day = LocalDay(year: 2026, month: 11, day: 2)
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.updateSettings(UserSettings(
            dailyGoal: .light,
            showTransliteration: false,
            placementTakenDay: day
        ))
        let item = try #require(ItemID(rawValue: "e-salam"))
        try await store.applyReconciliation([ReviewCard.introduced(itemID: item, on: day)])
        let before = try await store.load()
        #expect(before.cards.count == 1)
        #expect(before.settings.placementTakenDay == day)
        #expect(before.contentVersion == "2026.11.0")

        #expect(ProgressReset.snapshot(after: .cancel, from: before) == before)
        let loadedAfterCancel = try await store.load()
        #expect(loadedAfterCancel == before)

        let decided = ProgressReset.snapshot(after: .reset, from: before)
        try await store.resetAll()
        let after = try await store.load()
        #expect(after == decided)
        #expect(after.contentVersion == before.contentVersion)
        #expect(after.settings.dailyGoal == .light)
        #expect(after.settings.showTransliteration == false)
        #expect(after.settings.placementTakenDay == nil)
        #expect(after.cards.isEmpty)
        #expect(after.lessonProgress.isEmpty)
        #expect(after.streak == .initial)
        #expect(after.activeSession == nil)
        #expect(after.completedSessions.isEmpty)
        #expect(after.snapshotVersion == before.snapshotVersion)
    }

    @Test func resetLeavesProfileSettingsAndTheDialogNamesBothButtons() {
        let suite = "pashto.profile.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProfileSettings(appearance: .light, audioSpeed: .faster, textSizeOffset: -1)
        ProfileSettingsStore.save(settings, to: defaults)

        let kept = ProgressReset.profileSettings(after: .reset, from: settings)
        #expect(kept == settings)
        #expect(ProgressReset.profileSettings(after: .cancel, from: settings) == settings)
        #expect(ProfileSettingsStore.load(from: defaults) == settings)

        #expect(ProgressResetCopy.confirm != ProgressResetCopy.cancel)
        #expect(!ProgressResetCopy.confirm.isEmpty)
        #expect(!ProgressResetCopy.cancel.isEmpty)
        #expect(ProgressResetCopy.title == "Start over?")
        #expect(ProgressResetCopy.message == "Your lessons, words and streak start from the beginning. Your settings stay the same.")
        #expect(ProgressResetCopy.confirm == "Start over")
        #expect(ProgressResetCopy.cancel == "Cancel")
        #expect(ProgressResetCopy.helper == "Asks before anything is deleted.")
        #expect(ProgressResetCopy.button == "Reset progress")
    }

    @Test func profileAndTabCopyStayInEnglish() {
        let lines = TabCopy.all + [
            SpeakCopy.comingSoon,
            ProfileCopy.appearance,
            ProfileCopy.system,
            ProfileCopy.light,
            ProfileCopy.dark,
            ProfileCopy.audioSpeed,
            ProfileCopy.slower,
            ProfileCopy.normal,
            ProfileCopy.faster,
            ProfileCopy.audioNote,
            ProfileCopy.textSize,
            ProfileCopy.smaller,
            ProfileCopy.standard,
            ProfileCopy.larger,
            ProfileCopy.textSizeNote,
            ProfileCopy.dialect,
            ProfileCopy.kabul,
            ProfileCopy.moreDialects,
            ProgressResetCopy.button,
            ProgressResetCopy.helper,
            ProgressResetCopy.title,
            ProgressResetCopy.message,
            ProgressResetCopy.confirm,
            ProgressResetCopy.cancel,
        ]
        let banned = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet", "Innstillinger", "Søk"]
        for line in lines {
            #expect(!line.isEmpty)
            for marker in banned where line.contains(marker) {
                Issue.record("\(line) contains \(marker)")
            }
        }
        #expect(TabCopy.all == ["Home", "Learn", "Speak", "Practice", "Profile"])
        #expect(ProfileCopy.kabul == "Kabul")
        #expect(ProfileCopy.moreDialects == "More dialects coming later")
        #expect(SpeakCopy.comingSoon == "Coming soon")
        #expect(!lines.contains { $0.contains("Eastern") })
    }
}

struct WordBreakPolicyTests {
    @Test func wordsBreakOnlyAtSpacesAndHyphensStayInsideTheWord() {
        let shown = WordBreakPolicy.display("cha-haar shan-BA")
        #expect(WordBreakPolicy.strippingJoiners(shown) == "cha-haar shan-BA")
        let parts = shown.split(separator: " ", omittingEmptySubsequences: false)
        #expect(parts.count == 2)
        #expect(parts[0].contains("-"))
        #expect(parts[0].contains(WordBreakPolicy.wordJoiner))
        #expect(!parts[0].contains(" "))
        #expect(parts[1].contains(WordBreakPolicy.wordJoiner))
        #expect(!shown.contains("\u{2011}"))
    }

    /// Pashto is compared with the stored string itself. Stripping joiners
    /// would hide an inserted character that is not U+2060.
    @Test func pashtoDisplayEqualsTheBundledText() throws {
        let samples = ["پلار", "مور", "دوشنبه", "سه شنبه", "چهارشنبه", "څه غواړې"]
        for sample in samples {
            expectPashtoUnchanged(sample, sample)
        }

        let bundle = try loadCourse().bundle
        var kinds: [ContentKind: Int] = [:]
        var categories: Set<String> = []
        var foundSamples: Set<String> = []
        var checked = 0

        for item in bundle.items {
            kinds[item.kind, default: 0] += 1
            expectPashtoUnchanged(item.pashto, item.id.rawValue)
            checked += 1
            if samples.contains(item.pashto) {
                foundSamples.insert(item.pashto)
            }
            if let name = item.name {
                expectPashtoUnchanged(name, "\(item.id.rawValue) name")
            }
            for token in item.tokens ?? [] {
                expectPashtoUnchanged(token, "\(item.id.rawValue) token")
            }
            if let forms = item.forms {
                expectPashtoUnchanged(forms.isolated, "\(item.id.rawValue) isolated")
                expectPashtoUnchanged(forms.initial, "\(item.id.rawValue) initial")
                expectPashtoUnchanged(forms.medial, "\(item.id.rawValue) medial")
                expectPashtoUnchanged(forms.final, "\(item.id.rawValue) final")
            }
        }
        for entry in bundle.romanization.table {
            expectPashtoUnchanged(entry.letter, "romanization \(entry.ascii)")
        }
        for unit in bundle.units {
            categories.insert(unit.id.rawValue)
        }

        #expect(checked == bundle.items.count)
        #expect(checked > 0)
        #expect((kinds[.word] ?? 0) > 0)
        #expect((kinds[.phrase] ?? 0) > 0)
        #expect((kinds[.letter] ?? 0) > 0)
        #expect(categories.count == bundle.units.count)
        #expect(categories.contains("u-family"))
        #expect(categories.contains("u-time"))
        #expect(foundSamples == Set(["پلار", "مور", "دوشنبه", "سه شنبه", "چهارشنبه"]))
    }

    /// Grep of the app sources. A Pashto field passed to WordBreakPolicy,
    /// directly or through a view that applies it, fails this test.
    @Test func pashtoFieldsAreNotPassedToWordBreakPolicy() throws {
        let root = repositoryRoot()
        let files = try swiftFiles(under: root.appendingPathComponent("PashtoApp"))
        #expect(files.count > 5)

        var markers: Set<String> = []
        var gatedSinks: Set<String> = []
        var ungatedSinks: Set<String> = []
        var pashtoCalls = 0
        var englishCalls = 0

        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            let stripped = stripComments(source)
            if stripped.contains("struct LearnListScreen") { markers.insert("learn") }
            if stripped.contains("struct PashtoLine") { markers.insert("quiz") }
            if stripped.contains("struct DailyWordCard") { markers.insert("daily") }
            if stripped.contains("struct ProfileSettingsScreen") { markers.insert("profile") }
            if stripped.contains("struct StudyCardLines") { markers.insert("cards") }
            if stripped.contains("struct PronunciationNoteText") { markers.insert("notes") }
            if stripped.contains("struct CategoryCelebrationScreen") { markers.insert("celebration") }
            if stripped.contains("struct FamilyWordRowView") { markers.insert("family") }

            for type in topLevelTypes(in: stripped) where type.body.contains("WordBreakPolicy") {
                if wordBreakIsLatinGated(type.body) {
                    gatedSinks.insert(type.name)
                } else {
                    ungatedSinks.insert(type.name)
                }
                let tainted = taintedIdentifiers(in: type.body)
                for call in sourceCalls(in: type.body) where isWordBreakCall(call) {
                    if containsPashtoField(call.arguments) || argumentIdentifiers(call.arguments).contains(where: tainted.contains) {
                        Issue.record("\(url.lastPathComponent) passes Pashto into \(call.callee)")
                    }
                }
            }
        }

        #expect(markers == Set(["learn", "quiz", "daily", "profile", "cards", "notes", "celebration", "family"]))
        #expect(ungatedSinks.isEmpty)
        #expect(gatedSinks.contains("FittingWords"))

        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            let stripped = stripComments(source)
            for call in sourceCalls(in: stripped) {
                let file = url.lastPathComponent
                if isWordBreakCall(call) && containsPashtoField(call.arguments) {
                    Issue.record("\(file) passes a Pashto field to \(call.callee): \(call.arguments)")
                }
                if ungatedSinks.contains(call.callee) && containsPashtoField(call.arguments) {
                    Issue.record("\(file) passes Pashto to \(call.callee), which applies word break")
                }
                if gatedSinks.contains(call.callee) && containsPashtoField(call.arguments) {
                    pashtoCalls += 1
                    #expect(call.arguments.contains("joinLatinWords: false"), "\(file) \(call.callee)")
                    #expect(!call.arguments.contains("joinLatinWords: true"), "\(file) \(call.callee)")
                    #expect(!call.arguments.contains("WordBreakPolicy"), "\(file) \(call.callee)")
                }
                if gatedSinks.contains(call.callee) && call.arguments.contains(".english") {
                    englishCalls += 1
                    #expect(call.arguments.contains("joinLatinWords: true"), "\(file) \(call.callee)")
                }
            }
        }
        #expect(pashtoCalls >= 2)
        #expect(englishCalls >= 2)

        let study = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        let home = try source("PashtoApp/ContentView.swift")
        let quiz = try source("PashtoApp/Quiz/QuizScreen.swift")
        let glyph = try source("PashtoApp/Quiz/GlyphCard.swift")
        let match = try source("PashtoApp/Quiz/MatchingBoard.swift")

        let fitting = try section("struct FittingWords", until: "private struct FittingWidthKey", in: study)
        #expect(fitting.contains("guard joinLatinWords else { return word }"))
        #expect(fitting.contains("return WordBreakPolicy.display(word)"))
        #expect(wordBreakIsLatinGated(stripComments(fitting)))

        let learn = try section("struct LearnListScreen", until: "struct StudyPrimaryButtonStyle", in: study)
        #expect(learn.contains("text: row.pashto"))
        #expect(learn.contains("joinLatinWords: false"))
        #expect(learn.contains("text: row.english"))
        #expect(learn.contains("joinLatinWords: true"))
        #expect(!learn.contains("WordBreakPolicy"))

        let cards = try section("struct StudyCardLines", until: "struct PronunciationNoteText", in: study)
        #expect(cards.contains("Text(verbatim: card.pashto)"))
        #expect(!cards.contains("WordBreakPolicy"))

        let notes = try section("struct PronunciationNoteText", until: "enum StudyPalette", in: study)
        #expect(notes.contains("PronunciationNotes.displayLine"))
        #expect(!notes.contains("WordBreakPolicy"))

        let family = try section("private struct FamilyWordRowView", until: "private struct DailyGoalRing", in: home)
        #expect(family.contains("text: row.pashto"))
        #expect(family.contains("joinLatinWords: false"))
        #expect(family.contains("text: row.english"))
        #expect(family.contains("joinLatinWords: true"))
        let familyPashto = try section("private var pashto", until: "private struct DailyGoalRing", in: home)
        #expect(familyPashto.contains("joinLatinWords: false"))
        #expect(!familyPashto.contains("WordBreakPolicy"))

        let daily = try section("private struct DailyWordCard", until: "private struct DailyWordSpin", in: home)
        #expect(daily.contains("text: word.pashto"))
        #expect(!daily.contains("WordBreakPolicy"))

        let celebration = try section("struct CategoryCelebrationScreen", until: "private struct GirihStarStack", in: home)
        #expect(celebration.contains("CategoryCelebration.praise.pashto"))
        #expect(!celebration.contains("WordBreakPolicy"))

        let profile = try section("struct ProfileSettingsScreen", until: nil, in: home)
        #expect(profile.contains("TabCopy.profile"))
        #expect(!profile.contains("WordBreakPolicy"))
        #expect(!profile.contains(".pashto"))

        for (name, text) in [("QuizScreen", quiz), ("GlyphCard", glyph), ("MatchingBoard", match)] {
            #expect(text.contains("PashtoLine"), "\(name) draws Pashto")
            #expect(!text.contains("WordBreakPolicy"), "\(name) applies word break")
        }

        let banned = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet"]
        for relative in [
            "PashtoApp/Quiz/StudyCardScreen.swift",
            "PashtoApp/ContentView.swift",
            "Packages/PashtoCore/Sources/PashtoCore/Quiz/WordBreakPolicy.swift",
        ] {
            let text = try source(relative)
            for marker in banned where text.contains(marker) {
                Issue.record("\(relative) contains \(marker)")
            }
        }
    }

    private func expectPashtoUnchanged(_ text: String, _ label: String) {
        let shown = WordBreakPolicy.display(text)
        #expect(shown == text, "\(label) was rewritten")
        #expect(shown.unicodeScalars.elementsEqual(text.unicodeScalars), "\(label) scalars changed")
        #expect(!shown.unicodeScalars.contains { $0.value == 0x2060 }, "\(label) contains U+2060")
    }

    private func loadCourse() throws -> BundledCourse {
        let root = repositoryRoot()
        let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
        let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
        guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
            Issue.record("The bundled course did not decode")
            throw WordBreakSourceError.missing
        }
        return course
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func section(_ start: String, until end: String?, in source: String) throws -> String {
        let lower = try #require(source.range(of: start))
        let upper: String.Index
        if let end, let found = source.range(of: end, range: lower.upperBound..<source.endIndex) {
            upper = found.lowerBound
        } else {
            upper = source.endIndex
        }
        return String(source[lower.lowerBound..<upper])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}

private struct SourceCall {
    var callee: String
    var arguments: String
    var prefix: String
}

private struct SourceType {
    var name: String
    var body: String
}

private func isWordBreakCall(_ call: SourceCall) -> Bool {
    if call.callee.contains("WordBreakPolicy") { return true }
    let trimmed = call.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasSuffix("WordBreakPolicy.") || trimmed.hasSuffix("WordBreakPolicy")
}

private func containsPashtoField(_ text: String) -> Bool {
    text.range(
        of: #"(?<![A-Za-z0-9_])pashto(?![A-Za-z0-9_])|\.(?:isolated|initial|medial|final)\b|\.tokens(?!\()"#,
        options: .regularExpression
    ) != nil
}

private func argumentIdentifiers(_ arguments: String) -> Set<String> {
    var names: Set<String> = []
    let pattern = #"[A-Za-z_][A-Za-z0-9_]*"#
    var rest = arguments[...]
    while let match = rest.range(of: pattern, options: .regularExpression) {
        names.insert(String(rest[match]))
        rest = rest[match.upperBound...]
    }
    return names
}

private func taintedIdentifiers(in body: String) -> Set<String> {
    var tainted: Set<String> = []
    let pattern = #"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=\s*([^\n]+)"#
    var rest = body[...]
    while let match = rest.range(of: pattern, options: .regularExpression) {
        let line = String(rest[match])
        if let nameRange = line.range(of: #"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
            let name = line[nameRange].split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            let rhs = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            if containsPashtoField(rhs) {
                tainted.insert(name)
            }
        }
        rest = rest[match.upperBound...]
    }
    return tainted
}

private func wordBreakIsLatinGated(_ body: String) -> Bool {
    var search = body.startIndex
    var found = false
    while let range = body.range(of: "WordBreakPolicy", range: search..<body.endIndex) {
        found = true
        let prefix = body[..<range.lowerBound]
        guard let function = prefix.range(of: "func ", options: .backwards) else { return false }
        let beforeCall = body[function.lowerBound..<range.lowerBound]
        if !beforeCall.contains("guard joinLatinWords else") || !beforeCall.contains("return word") {
            return false
        }
        search = range.upperBound
    }
    return found
}

private func topLevelTypes(in source: String) -> [SourceType] {
    let pattern = #"(?m)^(?:public |private |internal |fileprivate |final |nonisolated |open )*(?:struct|enum|class|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    var types: [SourceType] = []
    var rest = source.startIndex
    while let match = source.range(of: pattern, options: .regularExpression, range: rest..<source.endIndex) {
        let header = String(source[match])
        let name = header.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard let open = source[match.upperBound...].firstIndex(of: "{") else { break }
        let close = matchingBrace(source, open)
        types.append(SourceType(name: name, body: String(source[source.index(after: open)..<close])))
        rest = source.index(after: close)
    }
    return types
}

private func matchingBrace(_ source: String, _ open: String.Index) -> String.Index {
    var depth = 0
    var index = open
    while index < source.endIndex {
        if source[index] == "\"" {
            index = skipString(source, index)
            continue
        }
        if source[index] == "{" {
            depth += 1
        } else if source[index] == "}" {
            depth -= 1
            if depth == 0 { return index }
        }
        index = source.index(after: index)
    }
    return source.index(before: source.endIndex)
}

private func sourceCalls(in source: String) -> [SourceCall] {
    var calls: [SourceCall] = []
    var index = source.startIndex
    while index < source.endIndex {
        if source[index] == "\"" {
            index = skipString(source, index)
            continue
        }
        if isIdentStart(source[index]) {
            let start = index
            index = source.index(after: index)
            while index < source.endIndex {
                if isIdent(source[index]) {
                    index = source.index(after: index)
                    continue
                }
                if source[index] == "." {
                    let next = source.index(after: index)
                    if next < source.endIndex, isIdentStart(source[next]) {
                        index = next
                        continue
                    }
                }
                break
            }
            var cursor = index
            while cursor < source.endIndex, source[cursor].isWhitespace {
                cursor = source.index(after: cursor)
            }
            if cursor < source.endIndex, source[cursor] == "(" {
                let end = matchingParen(source, cursor)
                let prefixStart = source.index(start, offsetBy: -80, limitedBy: source.startIndex) ?? source.startIndex
                calls.append(SourceCall(
                    callee: String(source[start..<index]),
                    arguments: String(source[source.index(after: cursor)..<end]),
                    prefix: String(source[prefixStart..<start])
                ))
                index = source.index(after: cursor)
                continue
            }
            continue
        }
        index = source.index(after: index)
    }
    return calls
}

private func matchingParen(_ source: String, _ open: String.Index) -> String.Index {
    var depth = 0
    var index = open
    while index < source.endIndex {
        if source[index] == "\"" {
            index = skipString(source, index)
            continue
        }
        if source[index] == "(" {
            depth += 1
        } else if source[index] == ")" {
            depth -= 1
            if depth == 0 { return index }
        }
        index = source.index(after: index)
    }
    return source.index(before: source.endIndex)
}

private func skipString(_ source: String, _ open: String.Index) -> String.Index {
    var index = source.index(after: open)
    while index < source.endIndex {
        if source[index] == "\\" {
            index = source.index(after: index)
            if index < source.endIndex {
                index = source.index(after: index)
            }
            continue
        }
        if source[index] == "\"" {
            return source.index(after: index)
        }
        index = source.index(after: index)
    }
    return index
}

private func stripComments(_ source: String) -> String {
    var result = ""
    var index = source.startIndex
    while index < source.endIndex {
        if source[index] == "\"" {
            let end = skipString(source, index)
            result.append(contentsOf: source[index..<end])
            index = end
            continue
        }
        let next = source.index(after: index)
        if source[index] == "/", next < source.endIndex, source[next] == "/" {
            index = source[next...].firstIndex(of: "\n").map { source.index(after: $0) } ?? source.endIndex
            result.append("\n")
            continue
        }
        if source[index] == "/", next < source.endIndex, source[next] == "*" {
            var cursor = source.index(after: next)
            while cursor < source.endIndex {
                let after = source.index(after: cursor)
                if source[cursor] == "*", after < source.endIndex, source[after] == "/" {
                    cursor = source.index(after: after)
                    break
                }
                cursor = after
            }
            index = cursor
            continue
        }
        result.append(source[index])
        index = next
    }
    return result
}

private func isIdentStart(_ character: Character) -> Bool {
    character == "_" || character.isLetter
}

private func isIdent(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
}

private enum WordBreakSourceError: Error {
    case missing
}
