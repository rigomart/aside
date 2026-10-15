import AppKit
import AsideCore
import SwiftUI

struct PanelView: View {
    let session: AssistantSession
    @State private var query = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask anything", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($inputFocused)
                .onSubmit(send)
            if !session.conversation.isEmpty {
                Divider()
                TranscriptView(conversation: session.conversation)
            }
            HStack {
                Text(claudeStatus)
                    .accessibilityIdentifier("claudeStatus")
                Spacer()
                if !session.conversation.isEmpty {
                    Button("New conversation ⌘N", action: session.startNewConversation)
                        .buttonStyle(.plain)
                        .keyboardShortcut("n")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 640, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            inputFocused = true
        }
    }

    /// Return sends. While an answer is still coming, Return does nothing and the text stays.
    private func send() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !session.conversation.isResponding else { return }
        session.send(question)
        query = ""
    }

    private var claudeStatus: String {
        switch session.claude {
        case .searching: "Looking for claude…"
        case .found(let path): "claude: \(path)"
        case .missing: AssistantSession.missingMessage
        }
    }
}

/// The questions and answers so far, newest at the bottom. Grows with its content up to a cap,
/// then scrolls, following the answer as it streams in.
private struct TranscriptView: View {
    let conversation: Conversation
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(conversation.exchanges) { ExchangeView(exchange: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, 420))
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ExchangeView: View {
    let exchange: Conversation.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let question = exchange.question {
                Text(question)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("question")
            }
            if !exchange.answer.isEmpty {
                Text(Self.inlineMarkdown(exchange.answer))
                    .accessibilityIdentifier("answer")
            }
            if !exchange.isFinished, exchange.activity != nil || exchange.answer.isEmpty {
                Text(exchange.activity ?? "Thinking…")
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("activity")
            }
            if let error = exchange.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("error")
            }
        }
        .font(.body)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Bold, italics, code and links render; anything else shows as typed, line breaks included.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
