import Testing
@testable import AsideCore

struct AnswerBlockTests {
    @Test func paragraphsKeepTheirLinesAndInlineMarks() {
        #expect(AnswerBlock.blocks("It's **sunny**.\nWarm too.\n\nTake a hat.") == [
            .paragraph("It's **sunny**.\nWarm too."),
            .paragraph("Take a hat."),
        ])
    }

    @Test func headingsAndListItems() {
        #expect(AnswerBlock.blocks("## Tips\n- Sleep early\n* Skip coffee\n2. Walk\n10) Read") == [
            .heading("Tips"),
            .item(marker: "•", text: "Sleep early"),
            .item(marker: "•", text: "Skip coffee"),
            .item(marker: "2.", text: "Walk"),
            .item(marker: "10.", text: "Read"),
        ])
    }

    @Test func emphasisAtTheStartIsNotAListItem() {
        #expect(AnswerBlock.blocks("**Huascarán** is tallest.") == [.paragraph("**Huascarán** is tallest.")])
    }

    @Test func codeKeepsItsIndentationAndRulesDisappear() {
        #expect(AnswerBlock.blocks("Run:\n```bash\nif true; then\n  ls -la\nfi\n```\n---\nDone.") == [
            .paragraph("Run:"),
            .code("if true; then\n  ls -la\nfi"),
            .paragraph("Done."),
        ])
    }

    @Test func codeStillStreamingShowsAsCode() {
        #expect(AnswerBlock.blocks("Run:\n```\nls -la") == [.paragraph("Run:"), .code("ls -la")])
    }

    @Test func tablesShowAsCode() {
        #expect(AnswerBlock.blocks("Prices:\n| Item | Cost |\n| --- | --- |\n| Tea | $3 |\nCheap.") == [
            .paragraph("Prices:"),
            .code("| Item | Cost |\n| --- | --- |\n| Tea | $3 |"),
            .paragraph("Cheap."),
        ])
    }
}
