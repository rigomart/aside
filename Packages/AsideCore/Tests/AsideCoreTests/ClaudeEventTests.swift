import Foundation
import Testing
@testable import AsideCore

/// Lines captured from Claude Code 2.1.300, trimmed of ids, unless a test says otherwise; the hook_callback line is made up.
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

    /// Captured from Claude Code 2.1.318, as are the next three.
    @Test func turnStartNamesItsSession() {
        #expect(parse(#"{"type":"system","subtype":"init","cwd":"/tmp/ws","session_id":"06e29be4-e027-4958-ace4-d61e8e3b020b","tools":["WebSearch","WebFetch"],"model":"claude-haiku-5-5"}"#)
            == .sessionStarted(id: "06e29be4-e027-4958-ace4-d61e8e3b020b"))
    }

    @Test func replyStartCountsTheContext() {
        let line = #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-5-5","id":"msg_1","type":"message","role":"assistant","content":[],"usage":{"input_tokens":2,"cache_creation_input_tokens":1678,"cache_read_input_tokens":5747,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1678},"output_tokens":8,"service_tier":"standard"}}}}"#
        #expect(parse(line) == .contextUsed(tokens: 7427))
    }

    @Test func compactionStartsAndEnds() {
        #expect(parse(#"{"type":"system","subtype":"status","status":"compacting","session_id":"4a67391d-ef05-4f33-9103-40e8dd6f02c5"}"#) == .compacting)
        #expect(parse(#"{"type":"system","subtype":"status","status":null,"compact_result":"success","session_id":"4a67391d-ef05-4f33-9103-40e8dd6f02c5"}"#) == nil)
        #expect(parse(#"{"type":"system","subtype":"status","status":"requesting","session_id":"4a67391d-ef05-4f33-9103-40e8dd6f02c5"}"#) == nil)
        let boundary = #"{"type":"system","subtype":"compact_boundary","session_id":"4a67391d-ef05-4f33-9103-40e8dd6f02c5","compact_metadata":{"trigger":"manual","pre_tokens":8406,"post_tokens":2148,"duration_ms":8730}}"#
        #expect(parse(boundary) == .compacted(id: "4a67391d-ef05-4f33-9103-40e8dd6f02c5"))
    }

    /// Captured from Claude Code 2.1.316 with `--permission-prompts host --permission-prompt-tool stdio`.
    @Test func permissionRequest() throws {
        let line = #"{"type":"control_request","request_id":"a57f1ebb","request":{"subtype":"can_use_tool","tool_name":"Write","display_name":"Write","input":{"file_path":"/tmp/hello.txt","content":"hi"},"description":"hello.txt","permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}],"tool_use_id":"toolu_01X5"}}"#
        let input = Data(#"{"content":"hi","file_path":"\/tmp\/hello.txt"}"#.utf8)
        #expect(parse(line) == .approvalRequested(ApprovalRequest(id: "a57f1ebb", tool: "Write", detail: "hello.txt", input: input)))
    }

    @Test func otherControlRequestsAreUnsupported() {
        #expect(parse(#"{"type":"control_request","request_id":"r1","request":{"subtype":"hook_callback","callback_id":"x"}}"#)
            == .unsupportedRequest(id: "r1", kind: "hook_callback"))
    }

    @Test func ignoresWhatAsideDoesNotUse() {
        #expect(parse(#"{"type":"system","subtype":"init","tools":["WebFetch","WebSearch"]}"#) == nil)
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#) == nil)
        #expect(parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}}"#) == nil)
        #expect(parse(#"{"type":"assistant","message":{"content":[]}}"#) == nil)
        #expect(parse("not json") == nil)
    }
}
