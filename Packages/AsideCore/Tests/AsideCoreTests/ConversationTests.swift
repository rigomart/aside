import Testing
@testable import AsideCore

struct ConversationTests {
    @Test func streamsAnAnswer() {
        var conversation = Conversation()
        conversation.ask("Hi?")
        #expect(conversation.isResponding)
        conversation.apply(.textStarted)
        conversation.apply(.text("Hel"))
        conversation.apply(.text("lo."))
        conversation.apply(.turnEnded(error: nil))
        #expect(!conversation.isResponding)
        #expect(conversation.exchanges.map(\.answer) == ["Hello."])
        #expect(conversation.exchanges[0].question == "Hi?")
    }

    @Test func separatesTextBeforeAndAfterATool() {
        var conversation = Conversation()
        conversation.ask("Weather?")
        conversation.apply(.textStarted)
        conversation.apply(.text("Checking."))
        conversation.apply(.toolStarted("WebSearch"))
        #expect(conversation.exchanges[0].activity == "Searching the web…")
        conversation.apply(.textStarted)
        conversation.apply(.text("Sunny."))
        #expect(conversation.exchanges[0].answer == "Checking.\n\nSunny.")
        #expect(conversation.exchanges[0].activity == nil)
    }

    @Test func failedTurnKeepsItsError() {
        var conversation = Conversation()
        conversation.ask("Hi?")
        conversation.apply(.turnEnded(error: "Rate limited"))
        #expect(conversation.exchanges[0].error == "Rate limited")
        #expect(!conversation.isResponding)
    }

    @Test func failureDuringATurnEndsIt() {
        var conversation = Conversation()
        conversation.ask("Hi?")
        conversation.fail("claude stopped")
        #expect(conversation.exchanges.count == 1)
        #expect(conversation.exchanges[0].error == "claude stopped")
        #expect(!conversation.isResponding)
    }

    @Test func failureBetweenTurnsGetsItsOwnLine() {
        var conversation = Conversation()
        conversation.fail("claude stopped")
        #expect(conversation.exchanges.count == 1)
        #expect(conversation.exchanges[0].question == nil)
        #expect(conversation.exchanges[0].error == "claude stopped")
        #expect(!conversation.isResponding)
    }

    @Test func ignoresEventsBetweenTurns() {
        var conversation = Conversation()
        conversation.apply(.text("stray"))
        #expect(conversation.isEmpty)
    }
}
