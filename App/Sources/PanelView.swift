import AppKit
import SwiftUI

@Observable
final class PanelModel {
    enum ClaudeStatus: Equatable {
        case searching
        case found(String)
        case missing
    }

    var query = ""
    var claude = ClaudeStatus.searching
}

struct PanelView: View {
    @Bindable var model: PanelModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask anything", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($inputFocused)
            Text(claudeStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("claudeStatus")
        }
        .padding(18)
        .frame(width: 640, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            inputFocused = true
        }
    }

    private var claudeStatus: String {
        switch model.claude {
        case .searching: "Looking for claude…"
        case .found(let path): "claude: \(path)"
        case .missing: "claude not found. Install Claude Code, or set its path in Settings."
        }
    }
}
