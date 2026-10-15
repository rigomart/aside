import Foundation

/// Writes executable scripts that stand in for `claude` into a fresh temporary folder.
struct FakeClaude {
    let directory = FileManager.default.temporaryDirectory.appending(path: "AsideCoreTests-\(UUID().uuidString)")

    /// Answers each message with "Answer <n>: <message>", counting from 1 per process.
    /// A message containing "boom" makes it write to stderr and exit with status 3.
    static let answering = #"""
        #!/bin/bash
        n=0
        while IFS= read -r line; do
          n=$((n+1))
          case "$line" in *boom*) echo "something broke" >&2; exit 3;; esac
          content=$(printf '%s' "$line" | sed -E 's/.*"content":("([^"\\]|\\.)*").*/\1/')
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
