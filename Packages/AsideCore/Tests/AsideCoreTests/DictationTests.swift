import Foundation
import Testing
@testable import AsideCore

@MainActor
struct DictationTests {
    let listener = FakeListener()

    /// Records pastes and answers with `result`.
    final class Clipboard {
        var pasted: [String] = []
        var result: Dictation.PasteResult = .pasted
    }

    let clipboard = Clipboard()

    func dictation(shownFor: Duration = .seconds(60)) -> Dictation {
        Dictation(listen: { [listener] in listener }, paste: { [clipboard] in
            clipboard.pasted.append($0)
            return clipboard.result
        }, shownFor: { _ in shownFor })
    }

    func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Condition not met after 5 s"); return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func secondPressPastesWhatWasHeard() async {
        let dictation = dictation()
        dictation.toggle()
        #expect(dictation.state == .starting("Starting the microphone…"))
        #expect(dictation.isDictating)
        listener.listen()
        listener.hear("Hello")
        listener.hear("Hello there. ")
        await eventually { dictation.state == .listening }

        dictation.toggle()
        #expect(dictation.state == .finishing)
        await eventually { dictation.state == .off }
        #expect(clipboard.pasted == ["Hello there."])
        #expect(!dictation.isDictating)
    }

    @Test func returnPastesToo() async {
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        listener.hear("Hi")
        await eventually { dictation.state == .listening }
        dictation.finish()
        await eventually { dictation.state == .off }
        #expect(clipboard.pasted == ["Hi"])
    }

    @Test func escPastesNothing() async {
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        listener.hear("Never mind")
        await eventually { dictation.state == .listening }
        dictation.cancel()
        #expect(dictation.state == .off)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(clipboard.pasted.isEmpty)
    }

    @Test func pressingBeforeTheMicrophoneIsOnStops() async {
        let dictation = dictation()
        dictation.toggle()
        dictation.toggle()
        #expect(dictation.state == .off)
        #expect(clipboard.pasted.isEmpty)
    }

    @Test func hearingNothingSaysSoAndPastesNothing() async {
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        listener.hear("  ")
        await eventually { dictation.state == .listening }
        dictation.toggle()
        await eventually { dictation.state == .message(.heardNothing) }
        #expect(dictation.state.message?.text == "Didn't hear anything")
        #expect(clipboard.pasted.isEmpty)
    }

    @Test func messagesGoAwayOnTheirOwn() async {
        let dictation = dictation(shownFor: .milliseconds(20))
        dictation.toggle()
        listener.listen()
        await eventually { dictation.state == .listening }
        dictation.toggle()
        await eventually { dictation.state == .message(.heardNothing) }
        await eventually { dictation.state == .off }
    }

    @Test func withoutAccessibilityItSaysWhy() async {
        clipboard.result = .needsAccessibility
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        listener.hear("Kept for later")
        await eventually { dictation.state == .listening }
        dictation.finish()
        await eventually { dictation.state == .message(.needsAccessibility) }
        #expect(clipboard.pasted == ["Kept for later"])
        #expect(!dictation.isDictating)
    }

    @Test func aListeningFailureShowsInThePill() async {
        let dictation = dictation()
        dictation.toggle()
        listener.fail("No microphone found.")
        await eventually { dictation.state == .message(.failed("No microphone found.")) }
        #expect(dictation.level == 0)
    }

    @Test func theLevelFollowsTheMicrophone() async {
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        listener.sound(0.6)
        await eventually { dictation.level == 0.6 }
        dictation.cancel()
        #expect(dictation.level == 0)
    }

    @Test func pressingWhileAMessageShowsStartsAgain() async {
        let dictation = dictation()
        dictation.toggle()
        listener.listen()
        await eventually { dictation.state == .listening }
        dictation.toggle()
        await eventually { dictation.state == .message(.heardNothing) }
        dictation.toggle()
        #expect(dictation.state == .starting("Starting the microphone…"))
    }
}

extension Dictation.State {
    var message: Dictation.Message? {
        if case .message(let message) = self { message } else { nil }
    }
}
