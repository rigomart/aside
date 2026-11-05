import Foundation

/// Writes executable scripts that stand in for `claude` into a fresh temporary folder.
struct FakeClaude {
    let directory = FileManager.default.temporaryDirectory.appending(path: "AsideCoreTests-\(UUID().uuidString)")

    /// Answers each message with "Answer <n>: <message>", counting from 1 per process.
    /// A message containing "boom" makes it write to stderr and exit with status 3. One containing
    /// "approve" asks to write note.md and answers "Allowed: wrote note.md." or "Denied: The owner declined."
    /// with what Aside replied; one containing "unhandled" sends a request Aside doesn't handle and answers
    /// "Refused." if Aside refused it. One starting with "remember" adds it as a fact to `../memory/MEMORY.md`,
    /// one containing "forget" removes the facts starting with "remember", and one containing "recall" answers
    /// "Knows a fact." if claude was started with one, else "Knows nothing.". One containing "autoMemory"
    /// answers with `CLAUDE_CODE_DISABLE_AUTO_MEMORY`.
    static let answering = #"""
        #!/bin/bash
        n=0
        while IFS= read -r line; do
          n=$((n+1))
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
          case "$line" in *recall*) case "$*" in *"- remember"*) content='"Knows a fact."';; *) content='"Knows nothing."';; esac;; esac
          case "$line" in *autoMemory*) content="\"$CLAUDE_CODE_DISABLE_AUTO_MEMORY\"";; esac
          echo '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}'
          echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Answer $n: \"}}}"
          echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":$content}}}"
          echo '{"type":"result","subtype":"success","is_error":false,"result":""}'
        done
        """#

    /// Writes `script` and returns its path.
    func write(_ script: String = Self.answering) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "claude-\(UUID().uuidString.prefix(6))")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
