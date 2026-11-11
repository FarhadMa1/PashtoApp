import Foundation
import Testing
@testable import PashtoCore

struct TravelTimeContentTests {
    @Test func travelAndTimeMatchTheApprovedRows() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let issues = ContentValidator.validate(bundle, mode: .release)
        #expect(!issues.contains { $0.severity == .error })

        #expect(bundle.units.map(\.id.rawValue) == [
            "u-sounds", "u-basics", "u-greetings", "u-introductions", "u-family",
            "u-travel", "u-time",
            "u-numbers", "u-food", "u-town", "u-conversation",
        ])
        #expect(course.releasedUnitIDs.map(\.rawValue) == [
            "u-basics", "u-greetings", "u-introductions", "u-family", "u-travel", "u-time",
            "u-numbers", "u-food", "u-town", "u-conversation",
        ])

        let travel = try unit("u-travel", in: bundle)
        let time = try unit("u-time", in: bundle)
        #expect(travel.title == "Travel")
        #expect(time.title == "Time and days")
        #expect(introducedIDs(travel).isDisjoint(with: introducedIDs(time)))
        #expect(bundle.items.filter { $0.id.rawValue == "e-tak-see" }.count == 1)
        #expect(bundle.items.filter { $0.id.rawValue == "e-baa-zaar-cher-ta-day" }.count == 1)

        for row in approvedRows {
            let item = try #require(bundle.items.first { $0.id.rawValue == row.id })
            #expect(item.pashto == row.pashto, "\(row.id) pashto")
            #expect(item.pronunciation == row.pronunciation, "\(row.id) pronunciation")
            #expect(item.en == row.english, "\(row.id) english")
            #expect(item.translit == row.translit, "\(row.id) translit")
            #expect(item.kind == row.kind, "\(row.id) kind")
            let introductions = bundle.units.flatMap { unit in
                unit.lessons.flatMap { lesson in
                    lesson.items.filter { $0.role == .introduce && $0.item.rawValue == row.id }.map { _ in unit.id.rawValue }
                }
            }
            #expect(introductions == [row.unit])
        }

        let taxi = try #require(bundle.items.first { $0.id.rawValue == "e-tak-see" })
        #expect(taxi.pashto == "ټکسي")
        #expect(taxi.pronunciation == "tak-SEE")
        #expect(taxi.en == "taxi")
        let market = try #require(bundle.items.first { $0.id.rawValue == "e-baa-zaar-cher-ta-day" })
        #expect(market.pashto == "بازار چېرته دی؟")
        #expect(market.pronunciation == "baa-ZAAR CHER-ta day?")

        expectLesson(
            "l-travel-learn-around", "Getting around", .learn,
            ["e-ha-waa-yee-da-gar", "e-ho-tal", "e-ti-kat", "e-tash-naab", "e-tak-see"],
            .present, in: travel
        )
        expectLesson(
            "l-travel-learn-money", "Money and help", .learn,
            ["e-pay-se", "e-graan", "e-ar-zaan", "e-mras-ta"],
            .present, in: travel
        )
        expectLesson(
            "l-travel-phrases-where", "Where is …?", .phrases,
            ["e-ho-tal-cher-ta-day", "e-tash-naab-cher-ta-day", "e-za-ha-waa-yee-da-gar-ta-dzam", "e-dal-ta-wu-dre-ga", "e-baa-zaar-cher-ta-day"],
            .present, in: travel
        )
        expectLesson(
            "l-travel-phrases-buying", "Buying and help", .phrases,
            ["e-za-ti-kat-ghwaa-ram", "e-daa-pa-tso-day", "e-der-graan-day", "e-mras-ta-wu-kray"],
            .present, in: travel
        )
        expectLesson(
            "l-travel-1", "Practice: Getting around", .practice,
            ["e-ha-waa-yee-da-gar", "e-ho-tal", "e-ti-kat", "e-tash-naab", "e-ho-tal-cher-ta-day", "e-tash-naab-cher-ta-day", "e-za-ha-waa-yee-da-gar-ta-dzam", "e-dal-ta-wu-dre-ga"],
            .introduce, in: travel
        )
        expectLesson(
            "l-travel-2", "Practice: Buying and help", .practice,
            ["e-pay-se", "e-graan", "e-ar-zaan", "e-mras-ta", "e-za-ti-kat-ghwaa-ram", "e-daa-pa-tso-day", "e-der-graan-day", "e-mras-ta-wu-kray"],
            .introduce, in: travel
        )
        expectLesson(
            "l-time-learn-times", "Times of day", .learn,
            ["e-wradz", "e-sa-haar", "e-maa-khaam", "e-shpa", "e-os", "e-pa-roon"],
            .present, in: time
        )
        expectLesson(
            "l-time-learn-days", "Days of the week", .learn,
            ["e-shan-ba", "e-yak-shan-ba", "e-do-shan-ba", "e-se-shan-ba", "e-cha-haar-shan-ba", "e-panj-shan-ba", "e-ju-ma"],
            .present, in: time
        )
        expectLesson(
            "l-time-phrases-day", "What day is it?", .phrases,
            ["e-nan-tsa-wradz-da", "e-nan-ju-ma-da", "e-sa-baa-shan-ba-da", "e-tso-ba-je-dee"],
            .present, in: time
        )
        expectLesson(
            "l-time-phrases-morning", "Morning and night", .phrases,
            ["e-sa-haar-mo-pa-khayr", "e-shpa-mo-pa-khayr", "e-za-os-dzam", "e-za-sa-haar-kaar-ka-wam"],
            .present, in: time
        )
        expectLesson(
            "l-time-1", "Practice: Times of day", .practice,
            ["e-wradz", "e-sa-haar", "e-maa-khaam", "e-shpa", "e-os", "e-pa-roon", "e-sa-haar-mo-pa-khayr", "e-shpa-mo-pa-khayr", "e-za-os-dzam", "e-za-sa-haar-kaar-ka-wam"],
            .introduce, in: time
        )
        expectLesson(
            "l-time-2", "Practice: Days of the week", .practice,
            ["e-shan-ba", "e-yak-shan-ba", "e-do-shan-ba", "e-se-shan-ba", "e-cha-haar-shan-ba", "e-panj-shan-ba", "e-ju-ma", "e-nan-tsa-wradz-da", "e-nan-ju-ma-da", "e-sa-baa-shan-ba-da", "e-tso-ba-je-dee"],
            .introduce, in: time
        )
    }

    @Test func menuListsSixUnitsAfterFamily() throws {
        let course = try loadCourse()
        let menu = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: [],
            listedLessons: []
        )
        #expect(menu.categories.map(\.id.rawValue) == [
            "u-basics", "u-greetings", "u-introductions", "u-family", "u-travel", "u-time",
            "u-numbers", "u-food", "u-town", "u-conversation",
        ])
        #expect(menu.categories.map(\.label) == [
            "Basics", "Greetings", "Introduction", "Family", "Travel", "Time",
            "Numbers", "Food", "Town", "Conversation",
        ])
        #expect(menu.categories.map(\.title) == [
            "The basics",
            "Greetings and politeness",
            "Introducing yourself",
            "Family",
            "Travel",
            "Time and days",
            "Numbers",
            "Food and drink",
            "Around town",
            "Putting it together",
        ])
    }

    @Test func familyPicturesResolveOnlyOnLearnCards() throws {
        let bundle = try loadCourse().bundle
        let members = try #require(StudyCourse.deck(for: lessonID("l-family-learn-members"), in: bundle))
        let pictured = members.cards.compactMap { card -> String? in
            guard let picture = FamilyPictures.picture(for: card.itemID, english: card.meaning, lessonKind: members.kind) else {
                return nil
            }
            #expect(picture.assetName == card.itemID.rawValue)
            #expect(picture.accessibilityLabel == card.meaning)
            let item = bundle.items.first { $0.id == card.itemID }
            #expect(picture.accessibilityLabel == item?.en)
            return card.itemID.rawValue
        }
        #expect(pictured == [
            "e-mor", "e-plar", "e-wror", "e-xor", "e-zoy", "e-lur", "e-koraney",
        ])
        #expect(FamilyPictures.itemIDs == [
            "e-mor", "e-plar", "e-wror", "e-xor", "e-zoy", "e-lur", "e-koraney",
            "e-ha-waa-yee-da-gar", "e-ho-tal", "e-ti-kat", "e-tash-naab", "e-tak-see", "e-pay-se",
            "e-wradz", "e-sa-haar", "e-maa-khaam", "e-shpa",
        ])

        for id in FamilyPictures.itemIDs {
            let itemID = itemID(id)
            let english = bundle.items.first { $0.id.rawValue == id }?.en
            #expect(FamilyPictures.picture(for: itemID, english: english, lessonKind: .learn)?.accessibilityLabel == english)
            #expect(FamilyPictures.picture(for: itemID, english: english, lessonKind: .phrases) == nil)
            #expect(FamilyPictures.picture(for: itemID, english: english, lessonKind: .practice) == nil)
            let asset = repositoryRoot()
                .appendingPathComponent("PashtoApp/Assets.xcassets")
                .appendingPathComponent("\(id).imageset")
                .appendingPathComponent("\(id).png")
            #expect(FileManager.default.fileExists(atPath: asset.path))
        }
        #expect(FamilyPictures.picture(for: itemID("e-tak-see"), english: "taxi", lessonKind: .learn)?.accessibilityLabel == "taxi")

        let phrases = try #require(StudyCourse.deck(for: lessonID("l-family-phrases-this"), in: bundle))
        #expect(phrases.cards.allSatisfy {
            FamilyPictures.picture(for: $0.itemID, english: $0.meaning, lessonKind: phrases.kind) == nil
        })

        var rng = SplitMix64(seed: 7)
        let practice = LessonSessionBuilder.build(
            for: lessonID("l-family-1"),
            in: bundle,
            seenLessonIDs: [lessonID("l-family-1")],
            releasedUnitIDs: nil,
            using: &rng
        )
        #expect(!practice.tasks.isEmpty)
        for id in askedIDs(practice.tasks) {
            #expect(FamilyPictures.picture(for: id, english: "mother", lessonKind: .practice) == nil)
        }

        let quiz = try String(
            contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"),
            encoding: .utf8
        )
        let card = try String(
            contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Quiz/StudyCardScreen.swift"),
            encoding: .utf8
        )
        #expect(!quiz.contains("FamilyPictures"))
        #expect(card.contains("FamilyPictures.picture"))
        let taskSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Packages/PashtoCore/Sources/PashtoCore/Quiz/MultipleChoice.swift"),
            encoding: .utf8
        )
        #expect(!taskSource.contains("assetName"))
    }

    @Test func travelAndTimePicturesResolveOnlyOnLearnCards() throws {
        let bundle = try loadCourse().bundle
        let pictured = [
            "l-travel-learn-around": ["e-ha-waa-yee-da-gar", "e-ho-tal", "e-ti-kat", "e-tash-naab", "e-tak-see"],
            "l-travel-learn-money": ["e-pay-se"],
            "l-time-learn-times": ["e-wradz", "e-sa-haar", "e-maa-khaam", "e-shpa"],
            "l-time-learn-days": [String](),
        ]
        for (lesson, expected) in pictured {
            let deck = try #require(StudyCourse.deck(for: lessonID(lesson), in: bundle))
            #expect(deck.kind == .learn)
            let shown = deck.cards.compactMap { card -> String? in
                guard let picture = FamilyPictures.picture(
                    for: card.itemID,
                    english: card.meaning,
                    lessonKind: deck.kind
                ) else {
                    return nil
                }
                #expect(picture.assetName == card.itemID.rawValue)
                #expect(picture.accessibilityLabel == card.meaning)
                return card.itemID.rawValue
            }
            #expect(shown == expected)
        }

        let picturedIDs = [
            "e-ha-waa-yee-da-gar", "e-ho-tal", "e-ti-kat", "e-tash-naab", "e-tak-see", "e-pay-se",
            "e-wradz", "e-sa-haar", "e-maa-khaam", "e-shpa",
        ]
        for id in picturedIDs {
            let item = itemID(id)
            let english = bundle.items.first { $0.id.rawValue == id }?.en
            #expect(FamilyPictures.picture(for: item, english: english, lessonKind: .learn)?.assetName == id)
            #expect(FamilyPictures.picture(for: item, english: english, lessonKind: .learn)?.accessibilityLabel == english)
            #expect(FamilyPictures.picture(for: item, english: english, lessonKind: .phrases) == nil)
            #expect(FamilyPictures.picture(for: item, english: english, lessonKind: .practice) == nil)
            let imageset = repositoryRoot()
                .appendingPathComponent("PashtoApp/Assets.xcassets")
                .appendingPathComponent("\(id).imageset")
            let names = try FileManager.default.contentsOfDirectory(atPath: imageset.path).sorted()
            #expect(names == ["Contents.json", "\(id).png"])
        }
        #expect(FamilyPictures.picture(for: itemID("e-tak-see"), english: "taxi", lessonKind: .learn)?.assetName == "e-tak-see")
        #expect(FileManager.default.fileExists(atPath: repositoryRoot()
            .appendingPathComponent("PashtoApp/Assets.xcassets/e-tak-see.imageset/e-tak-see.png").path))

        for lesson in ["l-travel-phrases-where", "l-travel-phrases-buying", "l-time-phrases-day", "l-time-phrases-morning"] {
            let deck = try #require(StudyCourse.deck(for: lessonID(lesson), in: bundle))
            #expect(deck.cards.allSatisfy {
                FamilyPictures.picture(for: $0.itemID, english: $0.meaning, lessonKind: deck.kind) == nil
            })
        }

        let seen = bundle.units.flatMap(\.lessons).map(\.id)
        for lesson in ["l-travel-1", "l-travel-2", "l-time-1", "l-time-2"] {
            var rng = SplitMix64(seed: 7)
            let practice = LessonSessionBuilder.build(
                for: lessonID(lesson),
                in: bundle,
                seenLessonIDs: seen,
                releasedUnitIDs: nil,
                using: &rng
            )
            #expect(!practice.tasks.isEmpty)
            for id in askedIDs(practice.tasks) {
                #expect(FamilyPictures.picture(for: id, english: "airport", lessonKind: .practice) == nil)
            }
        }

        let quiz = try String(
            contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"),
            encoding: .utf8
        )
        #expect(!quiz.contains("FamilyPictures"))
        #expect(!quiz.contains("FamilyWordList"))
        for id in picturedIDs {
            #expect(!quiz.contains(id))
        }
    }

    @Test func dayNamesAndPhrasesStayInTheirOwnWrongOptionPools() throws {
        let bundle = try loadCourse().bundle
        let seen = bundle.units.flatMap(\.lessons).map(\.id)
        let context = QuizContext(bundle: bundle, seenLessonIDs: seen)
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, $0) })

        let tuesday = try #require(items["e-se-shan-ba"])
        #expect(DialogResponse.replyShape(of: tuesday) == .phrase)
        let dayCandidates = Distractors.candidates(for: tuesday, in: context)
        #expect(dayCandidates.count >= 3)
        #expect(dayCandidates.contains { $0.itemID.rawValue == "e-shan-ba" })
        for candidate in dayCandidates {
            let item = try #require(items[candidate.itemID.rawValue])
            #expect(AnswerPool.dayNames.contains(item.id.rawValue))
        }

        let airport = try #require(items["e-ha-waa-yee-da-gar"])
        #expect(airport.kind == .word)
        #expect(DialogResponse.replyShape(of: airport) == .phrase)
        let airportCandidates = Distractors.candidates(for: airport, in: context)
        #expect(airportCandidates.count >= 3)
        for candidate in airportCandidates {
            let item = try #require(items[candidate.itemID.rawValue])
            #expect(!AnswerPool.dayNames.contains(item.id.rawValue))
            #expect(DialogResponse.replyShape(of: item) == .phrase)
        }

        let hotel = try #require(items["e-ho-tal"])
        let hotelCandidates = Distractors.candidates(for: hotel, in: context)
        #expect(hotelCandidates.count >= 2)
        for candidate in hotelCandidates {
            let item = try #require(items[candidate.itemID.rawValue])
            #expect(DialogResponse.replyShape(of: item) == .word)
            #expect(!AnswerPool.dayNames.contains(item.id.rawValue))
        }

        for lesson in ["l-travel-1", "l-travel-2", "l-time-1", "l-time-2"] {
            var rng = SplitMix64(seed: 11)
            let session = LessonSessionBuilder.build(
                for: lessonID(lesson),
                in: bundle,
                seenLessonIDs: seen,
                maxQuestions: nil,
                releasedUnitIDs: nil,
                using: &rng
            )
            let introduced = Distractors.introducedItems(in: lessonID(lesson), bundle: bundle)
            let asked = askedIDs(session.tasks)
            #expect(introduced.allSatisfy { asked.contains($0.id) }, "\(lesson) is missing a question")
        }
    }
}

private struct ApprovedRow {
    var id: String
    var pashto: String
    var pronunciation: String
    var english: String
    var translit: String
    var kind: ContentKind
    var unit: String
}

private let approvedRows: [ApprovedRow] = [
    ApprovedRow(id: "e-ha-waa-yee-da-gar", pashto: "هوایي ډګر", pronunciation: "ha-waa-YEE da-GAR", english: "airport", translit: "hawāyí ḍagár", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-ho-tal", pashto: "هوټل", pronunciation: "ho-TAL", english: "hotel", translit: "hoṭál", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-ti-kat", pashto: "ټکټ", pronunciation: "ti-KAT", english: "ticket", translit: "ṭikáṭ", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-tash-naab", pashto: "تشناب", pronunciation: "tash-NAAB", english: "toilet, bathroom", translit: "tašnā́b", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-pay-se", pashto: "پیسې", pronunciation: "pay-SE", english: "money", translit: "paysé", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-graan", pashto: "ګران", pronunciation: "graan", english: "expensive", translit: "grān", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-ar-zaan", pashto: "ارزان", pronunciation: "ar-ZAAN", english: "cheap", translit: "arzā́n", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-mras-ta", pashto: "مرسته", pronunciation: "MRAS-ta", english: "help", translit: "mrásta", kind: .word, unit: "u-travel"),
    ApprovedRow(id: "e-ho-tal-cher-ta-day", pashto: "هوټل چېرته دی؟", pronunciation: "ho-TAL CHER-ta day?", english: "where is the hotel?", translit: "hoṭál čérta day?", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-tash-naab-cher-ta-day", pashto: "تشناب چېرته دی؟", pronunciation: "tash-NAAB CHER-ta day?", english: "where is the toilet?", translit: "tašnā́b čérta day?", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-za-ha-waa-yee-da-gar-ta-dzam", pashto: "زه هوایي ډګر ته ځم", pronunciation: "za ha-waa-YEE da-GAR ta dzam", english: "I am going to the airport", translit: "zə hawāyí ḍagár tə dzəm", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-dal-ta-wu-dre-ga", pashto: "دلته ودرېږه", pronunciation: "DAL-ta wu-DRE-ga", english: "stop here", translit: "dálta wdréǧa", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-za-ti-kat-ghwaa-ram", pashto: "زه ټکټ غواړم", pronunciation: "za ti-KAT ghwaa-RAM", english: "I would like a ticket", translit: "zə ṭikáṭ ɣwāṛə́m", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-daa-pa-tso-day", pashto: "دا په څو دی؟", pronunciation: "daa pa tso day?", english: "how much is this?", translit: "dā pə tso day?", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-der-graan-day", pashto: "ډېر ګران دی", pronunciation: "der graan day", english: "it's too expensive", translit: "ḍer grān day", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-mras-ta-wu-kray", pashto: "مرسته وکړئ!", pronunciation: "MRAS-ta wu-KRAY!", english: "help, please!", translit: "mrásta wkṛəy!", kind: .phrase, unit: "u-travel"),
    ApprovedRow(id: "e-wradz", pashto: "ورځ", pronunciation: "wradz", english: "day", translit: "wradz", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-sa-haar", pashto: "سهار", pronunciation: "sa-HAAR", english: "morning", translit: "sahā́r", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-maa-khaam", pashto: "ماښام", pronunciation: "maa-KHAAM", english: "evening", translit: "māx̌ā́m", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-shpa", pashto: "شپه", pronunciation: "shpa", english: "night", translit: "špa", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-os", pashto: "اوس", pronunciation: "os", english: "now", translit: "os", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-pa-roon", pashto: "پرون", pronunciation: "pa-ROON", english: "yesterday", translit: "parún", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-shan-ba", pashto: "شنبه", pronunciation: "shan-BA", english: "Saturday", translit: "šanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-yak-shan-ba", pashto: "یکشنبه", pronunciation: "yak-shan-BA", english: "Sunday", translit: "yakšanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-do-shan-ba", pashto: "دوشنبه", pronunciation: "do-shan-BA", english: "Monday", translit: "došanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-se-shan-ba", pashto: "سه شنبه", pronunciation: "se-shan-BA", english: "Tuesday", translit: "sešanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-cha-haar-shan-ba", pashto: "چهارشنبه", pronunciation: "cha-haar-shan-BA", english: "Wednesday", translit: "čahāršanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-panj-shan-ba", pashto: "پنجشنبه", pronunciation: "panj-shan-BA", english: "Thursday", translit: "panjšanbá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-ju-ma", pashto: "جمعه", pronunciation: "ju-MA", english: "Friday", translit: "jumá", kind: .word, unit: "u-time"),
    ApprovedRow(id: "e-nan-tsa-wradz-da", pashto: "نن څه ورځ ده؟", pronunciation: "nan tsa wradz da?", english: "what day is it today?", translit: "nan tsə wradz da?", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-nan-ju-ma-da", pashto: "نن جمعه ده", pronunciation: "nan ju-MA da", english: "today is Friday", translit: "nan jumá da", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-sa-baa-shan-ba-da", pashto: "سبا شنبه ده", pronunciation: "sa-BAA shan-BA da", english: "tomorrow is Saturday", translit: "sabā́ šanbá da", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-tso-ba-je-dee", pashto: "څو بجې دي؟", pronunciation: "tso ba-JE dee?", english: "what time is it?", translit: "tso badžé di?", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-sa-haar-mo-pa-khayr", pashto: "سهار مو په خیر", pronunciation: "sa-HAAR mo pa KHAYR", english: "good morning", translit: "sahā́r mo pə xayr", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-shpa-mo-pa-khayr", pashto: "شپه مو په خیر", pronunciation: "shpa mo pa KHAYR", english: "good night", translit: "špa mo pə xayr", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-za-os-dzam", pashto: "زه اوس ځم", pronunciation: "za os dzam", english: "I am going now", translit: "zə os dzəm", kind: .phrase, unit: "u-time"),
    ApprovedRow(id: "e-za-sa-haar-kaar-ka-wam", pashto: "زه سهار کار کوم", pronunciation: "za sa-HAAR kaar ka-WAM", english: "I work in the morning", translit: "zə sahā́r kār kawə́m", kind: .phrase, unit: "u-time"),
]

private func introducedIDs(_ unit: CourseUnit) -> Set<String> {
    Set(unit.lessons.flatMap { lesson in
        lesson.items.filter { $0.role == .introduce }.map(\.item.rawValue)
    })
}

private func askedIDs(_ tasks: [SessionTask]) -> Set<ItemID> {
    var ids: Set<ItemID> = []
    for task in tasks {
        switch task.payload {
        case .choice(let quiz):
            ids.insert(quiz.targetID)
        case .matchPairs(let match):
            for pair in match.pairs {
                ids.insert(pair.left.itemID)
            }
        case .orderWords(let order):
            ids.insert(order.targetID)
        }
    }
    return ids
}

private func expectLesson(
    _ id: String,
    _ title: String,
    _ kind: LessonKind,
    _ items: [String],
    _ role: LessonItemRole,
    in unit: CourseUnit
) {
    let lesson = unit.lessons.first { $0.id.rawValue == id }
    #expect(lesson?.title == title)
    #expect(lesson?.kind == kind)
    #expect(lesson?.items.map(\.item.rawValue) == items)
    #expect(lesson?.items.allSatisfy { $0.role == role } == true)
}

private func unit(_ id: String, in bundle: ContentBundle) throws -> CourseUnit {
    try #require(bundle.units.first { $0.id.rawValue == id })
}

private func loadCourse() throws -> BundledCourse {
    let root = repositoryRoot()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw TravelTimeTestError.missing
    }
    return course
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private enum TravelTimeTestError: Error {
    case missing
}
