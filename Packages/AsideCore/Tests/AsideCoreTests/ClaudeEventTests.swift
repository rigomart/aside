import Foundation
import Testing
@testable import AsideCore

/// Lines captured from Claude Code 2.1.300, trimmed of ids.
struct ClaudeEventTests {
    func parse(_ line: String) -> ClaudeEvent? {
        ClaudeEvent(json: Data(line.utf8))
    }

    @Test func textBlockStart() {
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#) == .textStarted)
    }

    @Test func textDelta() {
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"No, my instructions don't"}}}"#) == .text("No, my instructions don't"))
    }

    @Test func toolStart() {
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"WebSearch","input":{},"caller":{"type":"direct"}}}}"#) == .toolStarted("WebSearch"))
    }

    @Test func successfulResult() {
        #expect(parse(#"{"type":"result","subtype":"success","is_error":false,"result":"No."}"#) == .turnEnded(error: nil))
    }

    @Test func failedResultCarriesItsMessage() {
        let line = #"{"type":"result","subtype":"success","is_error":true,"result":"There's an issue with the selected model (nosuchmodel)."}"#
        #expect(parse(line) == .turnEnded(error: "There's an issue with the selected model (nosuchmodel)."))
    }

    @Test func errorSubtypeWithoutResultStillEndsTheTurn() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":[{"message":"x"}]}"#
        #expect(parse(line) == .turnEnded(error: "error_during_execution"))
    }

    @Test func ignoresWhatAsideDoesNotUse() {
        #expect(parse(#"{"type":"system","subtype":"init","tools":["WebFetch","WebSearch"]}"#) == nil)
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#) == nil)
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}}"#) == nil)
        #expect(parse(#"{"type":"assistant","message":{"content":[]}}"#) == nil)
        #expect(parse("not json") == nil)
    }
}
