import Testing
@testable import AsideCore

struct SpokenTextTests {
    @Test func formattingMarksAreLeftOut() {
        #expect(SpokenText.prose("It's **really** _quite_ *good*, see `brew install`.") == "It's really quite good, see brew install.")
        #expect(SpokenText.prose("Use snake_case names.") == "Use snake_case names.")
        #expect(SpokenText.prose("~~Old~~ new.") == "Old new.")
    }

    @Test func linksAreReadAsTheirTextAndAddressesAsTheSite() {
        #expect(SpokenText.prose("Read [the guide](https://example.com/guide).") == "Read the guide.")
        #expect(SpokenText.prose("It's on https://www.apple.com/macos/ today.") == "It's on apple.com today.")
        #expect(SpokenText.prose("![A chart](chart.png)Done.") == "Done.")
    }

    @Test func headingsListsAndQuotesLoseTheirMarksAndGetAPause() {
        let markdown = "# Plan\n- Milk\n* Eggs\n2. Bread\n> Quoted"
        #expect(SpokenText.prose(markdown) == "Plan.\nMilk.\nEggs.\nBread.\nQuoted")
    }

    @Test func codeBlocksTablesAndRulesAreSkipped() {
        let markdown = "Run this:\n```bash\nls -la\n```\n| a | b |\n|---|---|\n---\nThen restart."
        #expect(SpokenText.prose(markdown) == "Run this:\nThen restart.")
    }

    @Test func aCodeBlockStillComingIsSkipped() {
        #expect(SpokenText.prose("Here:\n```swift\nlet x = 1\nprint(x") == "Here:")
    }

    @Test func theLastSentenceWaitsUnlessAsked() {
        let text = "Dr. Smith is in. It costs $3.50 today! And then"
        let waiting = SpokenText.sentences(in: text, after: 0, includingLast: false)
        #expect(waiting.sentences == ["Dr. Smith is in.", "It costs $3.50 today!"])
        let rest = SpokenText.sentences(in: text, after: waiting.end, includingLast: true)
        #expect(rest.sentences == ["And then"])
        #expect(rest.end == text.count)
    }

    @Test func nothingCompleteSaysNothing() {
        let result = SpokenText.sentences(in: "Hello wor", after: 0, includingLast: false)
        #expect(result.sentences.isEmpty)
        #expect(result.end == 0)
    }

    @Test func blankLinesAndBarePunctuationAreNotSentences() {
        #expect(SpokenText.sentences(in: "One.\n\nTwo.\n.", after: 0, includingLast: true).sentences == ["One.", "Two."])
    }
}
