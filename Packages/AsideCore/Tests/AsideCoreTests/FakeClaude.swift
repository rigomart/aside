import Foundation

/// Writes executable scripts that stand in for `claude` into a fresh temporary folder.
struct FakeClaude {
    let directory = FileManager.default.temporaryDirectory.appending(path: "AsideCoreTests-\(UUID().uuidString)")

    /// Answers each message with "Answer <n>: <message>", n counting the session's messages from 1.
    /// Sessions are files in `.sessions/` in the folder it runs in, so `--resume <id>` continues the count,
    /// `--fork-session` copies the session under a new ID, and resuming one that doesn't exist fails as
    /// claude does. Each turn reports its session and a context of 1,000 tokens plus 100,000 for each
    /// question containing "big". "/compact" takes 0.3 s and leaves the session holding one line,
    /// "summary:" and the summarized messages' contents, which counts as one message and isn't big.
    /// A message containing "boom" makes it write to stderr and exit with status 3. One containing
    /// "approve" asks to write note.md and answers "Allowed: wrote note.md." or "Denied: The owner declined."
    /// with what Aside replied; one containing "unhandled" sends a request Aside doesn't handle and answers
    /// "Refused." if Aside refused it. One starting with "remember" adds it as a fact to `../memory/MEMORY.md`,
    /// one containing "forget" removes the facts starting with "remember", and one containing "recall" answers
    /// "Knows a fact." if claude was started with one, else "Knows nothing.". One containing "autoMemory"
    /// answers with `CLAUDE_CODE_DISABLE_AUTO_MEMORY`.
    static let answering = #"""
        #!/bin/bash
        sessions=.sessions; mkdir -p "$sessions"
        args="$*"; session=$(uuidgen); resume=""; fork=""
        while [ $# -gt 0 ]; do case "$1" in --resume) resume="$2"; shift;; --fork-session) fork=1;; esac; shift; done
        if [ -n "$resume" ]; then
          [ -f "$sessions/$resume" ] || { echo "No conversation found with session ID: $resume" >&2; exit 1; }
          if [ -n "$fork" ]; then cp "$sessions/$resume" "$sessions/$session"; else session="$resume"; fi
        fi
        touch "$sessions/$session"
        while IFS= read -r line; do
          if [ "$line" = '{"message":{"content":"/compact","role":"user"},"type":"user"}' ]; then
            echo "{\"type\":\"system\",\"subtype\":\"status\",\"status\":\"compacting\",\"session_id\":\"$session\"}"
            sleep 0.3
            summary="summary: $(sed -E 's/.*"content":"(([^"\\]|\\.)*)".*/\1/' "$sessions/$session" | tr '\n' ' ')"
            echo "$summary" > "$sessions/$session"
            echo "{\"type\":\"system\",\"subtype\":\"compact_boundary\",\"session_id\":\"$session\"}"
            echo '{"type":"result","subtype":"success","is_error":false,"result":""}'
            continue
          fi
          echo "$line" >> "$sessions/$session"
          n=$(wc -l < "$sessions/$session" | tr -d ' ')
          echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"$session\"}"
          echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":1000,\"cache_read_input_tokens\":$(( $(grep -v '^summary:' "$sessions/$session" | grep -c big) * 100000 )),\"cache_creation_input_tokens\":0}}}}"
          case "$line" in *boom*) echo "something broke" >&2; exit 3;; esac
          content=$(printf '%s' "$line" | sed -E 's/.*"content":("([^"\\]|\\.)*").*/\1/')
          case "$line" in *approve*)
            echo '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"Write","input":{}}}}'
            echo "{\"type\":\"control_request\",\"request_id\":\"req-$n\",\"request\":{\"subtype\":\"can_use_tool\",\"tool_name\":\"Write\",\"input\":{\"file_path\":\"note.md\",\"content\":\"hi\"},\"description\":\"note.md\"}}"
            IFS= read -r reply
            case "$reply" in
              *"\"request_id\":\"req-$n\""*'"behavior":"allow","updatedInput":{"content":"hi","file_path":"note.md"}'*) content='"Allowed: wrote note.md."';;
              *"\"request_id\":\"req-$n\""*'"behavior":"deny","message":"The owner declined."'*) content='"Denied: The owner declined."';;
              *) content='"Unexpected reply."';;
            esac;;
          esac
          case "$line" in *unhandled*)
            echo "{\"type\":\"control_request\",\"request_id\":\"req-$n\",\"request\":{\"subtype\":\"hook_callback\"}}"
            IFS= read -r reply
            case "$reply" in *'"error":"Aside doesn'"'"'t handle hook_callback requests."'*"\"request_id\":\"req-$n\""*'"subtype":"error"'*) content='"Refused."';; *) content='"Unexpected reply."';; esac;;
          esac
          case "$line" in *'"content":"remember'*)
            echo '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"Edit","input":{}}}}'
            echo "- ${content:1:${#content}-2}" >> ../memory/MEMORY.md;;
          esac
          case "$line" in *forget*)
            echo '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"Edit","input":{}}}}'
            sed -i '' '/^- remember/d' ../memory/MEMORY.md;;
          esac
          case "$line" in *recall*) case "$args" in *"- remember"*) content='"Knows a fact."';; *) content='"Knows nothing."';; esac;; esac
          case "$line" in *autoMemory*) content="\"$CLAUDE_CODE_DISABLE_AUTO_MEMORY\"";; esac
          echo '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}'
          echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Answer $n: \"}}}"
          echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":$content}}}"
          echo '{"type":"result","subtype":"success","is_error":false,"result":""}'
        done
        """#

    /// `answering`, written once for the whole run. macOS checks each new executable before its first run,
    /// and with one copy per test, late tests' fakes took over 5 s to start.
    static let sharedAnswering: Result<String, any Error> = Result {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AsideCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "claude")
        try answering.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// Creates this fake's folder and returns the path of `answering`, or of `script` written into the folder.
    func write(_ script: String = Self.answering) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if script == Self.answering { return try Self.sharedAnswering.get() }
        let url = directory.appending(path: "claude-\(UUID().uuidString.prefix(6))")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
