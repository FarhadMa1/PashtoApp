import Foundation
import Testing
@testable import PashtoCore

struct GreetingsAudioTests {
    @Test func itemWithAFileReturnsItsURLAndAnItemWithoutReturnsNil() throws {
        let directory = audioDirectory()
        let salam = try #require(ItemID(rawValue: "e-salam"))
        let url = try #require(GreetingsAudio.url(for: salam, in: directory))
        #expect(url.lastPathComponent == "e-salam.m4a")
        #expect(FileManager.default.fileExists(atPath: url.path))

        let letter = try #require(ItemID(rawValue: "e-letter-alif"))
        #expect(GreetingsAudio.url(for: letter, in: directory) == nil)

        let names = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "m4a" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        #expect(names.count == 19)
        for name in names {
            let id = try #require(ItemID(rawValue: name))
            let found = try #require(GreetingsAudio.url(for: id, in: directory))
            #expect(found.lastPathComponent == "\(name).m4a")
        }
    }

    @Test func theQuizDoesNotOfferTheClip() throws {
        let root = repositoryRoot()
        let quiz = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"), encoding: .utf8)
        let study = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/StudyCardScreen.swift"), encoding: .utf8)
        #expect(!quiz.contains("GreetingsAudio"))
        #expect(!quiz.contains("GreetingsClipPlayer"))
        #expect(study.contains("deck.unitID.rawValue == GreetingsAudio.unitID"))
        #expect(study.contains("GreetingsAudio.url"))
        #expect(study.components(separatedBy: "clipPlayer.play").count == 2)
        #expect(study.contains("accessibilityLabel(Text(verbatim: \"Play\"))"))
    }

    private func audioDirectory() -> URL {
        repositoryRoot().appendingPathComponent("PashtoApp/Audio")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
