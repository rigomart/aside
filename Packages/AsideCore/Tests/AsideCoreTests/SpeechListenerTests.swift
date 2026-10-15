import Foundation
import Testing
@testable import AsideCore

/// Real on-device recognition of a file that `say` speaks. CI runners have no speech model, and
/// downloading one there is slow and depends on Apple's servers, so these run on the owner's Mac only.
@Suite(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "No speech model on CI runners"))
struct SpeechListenerTests {
    func spoken(_ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AsideCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "spoken.m4a")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--file-format=m4af", "--data-format=aac", text]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)
        return url
    }

    @Test(.timeLimit(.minutes(1)))
    func hearsAFileAndFinishesWithTheLastWords() async throws {
        let listener = SpeechListener(source: .file(try spoken("What is the tallest mountain in Peru")))
        var events: [ListenerEvent] = []
        for try await event in listener.events {
            events.append(event)
            if event == .heard("What is the tallest mountain in Peru?") { listener.finish() }
        }
        #expect(events.contains(.listening))
        #expect(events.last == .heard("What is the tallest mountain in Peru?"))
        // Words arrive as they are spoken, not all at once.
        #expect(events.count(where: { if case .heard = $0 { true } else { false } }) > 2)
    }

    @Test func aMissingFileSaysSo() async throws {
        let listener = SpeechListener(source: .file(URL(fileURLWithPath: "/nonexistent/spoken.m4a")))
        await #expect(throws: ListenError.self) {
            for try await _ in listener.events {}
        }
    }
}

@Test func finalResultsJoinWithOneSpace() {
    #expect(joined("Hello there.", " How are you?") == "Hello there. How are you?")
    #expect(joined("Hello", "world") == "Hello world")
    #expect(joined("", " First") == "First")
}
