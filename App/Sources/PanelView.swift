import AppKit
import AsideCore
import KeyboardShortcuts
import SwiftUI

/// From the bottom up: a glass pill holding the field, a card with bars that move with the voice while
/// talking, a red line when something's wrong, and a card with the newest answer. While listening the
/// pill's edge breathes in blue; while an answer is read aloud, the card lights up the sentence being said.
struct PanelView: View {
    let session: AssistantSession
    let composer: Composer
    @FocusState private var inputFocused: Bool

    /// Room around the glass for the listening glow and the shadows.
    private static let margin: CGFloat = 20
    private static let width: CGFloat = 440
    private static let pillHeight: CGFloat = 52
    /// The glow and the voice bars.
    static let listeningColor = Color(red: 0.30, green: 0.55, blue: 1.0)

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .trailing, spacing: 10) {
                if let exchange = session.conversation.exchanges.last {
                    AnswerCard(
                        exchange: exchange,
                        caption: session.caption,
                        startNewConversation: session.startNewConversation
                    )
                }
                if composer.voice != .off {
                    voiceCard
                }
                if hasProblem {
                    problem
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }
                pill
            }
            .frame(width: Self.width)
        }
        // Outside the container, which draws its glass over anything inside it.
        .overlay(alignment: .bottom) {
            if composer.voice != .off { BreathingHalo().frame(height: Self.pillHeight) }
        }
        .padding(Self.margin)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            inputFocused = true
        }
    }

    private var pill: some View {
        HStack(spacing: 12) {
            // Closures, not method references: Xcode 26.6's compiler crashes on `set: composer.edit`.
            TextField(placeholder, text: Binding(get: { composer.text }, set: { composer.edit($0) }))
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($inputFocused)
                .onSubmit { composer.submit() }
                .accessibilityIdentifier("askField")
            Button(action: composer.toggleTalking) {
                Image(systemName: composer.voice == .off ? "mic" : "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: composer.voice != .off)
                    .font(.title3)
                    .foregroundStyle(composer.voice == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Self.listeningColor))
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(composer.voice == .off ? "Talk" : "Send")
            .accessibilityIdentifier("talkButton")
        }
        .padding(.horizontal, 20)
        .frame(height: Self.pillHeight)
        .glassEffect(.regular, in: .capsule)
    }

    private var placeholder: String {
        session.conversation.isEmpty ? "Ask, or \(talkShortcut) to talk" : "Ask a follow-up"
    }

    /// While talking: the voice as bars, and under them what the microphone is doing.
    private var voiceCard: some View {
        VStack(spacing: 10) {
            VoiceBars(level: composer.level)
            Group {
                switch composer.voice {
                case .off: EmptyView()
                case .starting(let reason): voiceStatus(reason)
                case .listening:
                    HStack(spacing: 6) {
                        Keycap(talkShortcut)
                        Text("sends")
                        Keycap("esc").padding(.leading, 6)
                        Text("cancels")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Listening · \(talkShortcut) sends · Esc cancels")
                    .accessibilityIdentifier("voiceStatus")
                case .finishing: voiceStatus("Sending…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func voiceStatus(_ text: String) -> some View {
        Text(text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("voiceStatus")
    }

    private var hasProblem: Bool {
        composer.voiceMessage != nil || session.claude == .missing
    }

    /// Above the pill, in red: why listening stopped, or that claude is missing.
    @ViewBuilder private var problem: some View {
        if let message = composer.voiceMessage {
            Label(message, systemImage: "mic.slash")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("voiceMessage")
        } else if session.claude == .missing {
            Text(AssistantSession.missingMessage)
                .foregroundStyle(.red)
                .accessibilityIdentifier("claudeStatus")
        }
    }

    private var talkShortcut: String {
        KeyboardShortcuts.getShortcut(for: .talk)?.description ?? "the talk shortcut"
    }
}

/// The newest question's answer: what Claude is doing until text arrives, then the answer, formatted.
/// While it's read aloud, the answer shows as captions instead, the sentence being said lit up.
private struct AnswerCard: View {
    let exchange: Conversation.Exchange
    let caption: Caption?
    let startNewConversation: () -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = exchange.question {
                Text(question)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("question")
            }
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 300))
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !exchange.answer.isEmpty {
                Group {
                    if let caption {
                        Text(Self.captioned(caption))
                            .font(.system(size: 17, weight: .medium))
                    } else {
                        Text(Self.formatted(exchange.answer))
                            .font(.system(size: 15))
                            .lineSpacing(2)
                    }
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("error")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if caption != nil {
                HStack(spacing: 8) {
                    Chip { Label("Reading", systemImage: "waveform").symbolEffect(.variableColor.iterative) }
                    Chip { Text("Esc stops") }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reading aloud. Esc stops.")
                .accessibilityIdentifier("readingStatus")
            }
            Spacer()
            Button(action: startNewConversation) {
                Chip { Text("New  ⌘N") }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n")
            .accessibilityLabel("New conversation")
            .accessibilityIdentifier("newConversation")
        }
        .font(.caption)
    }

    /// What was said dimmed, the sentence being said bright, and what's still to come faint.
    private static func captioned(_ caption: Caption) -> AttributedString {
        let parts: [(String, Color)] = [(caption.said, .secondary), (caption.saying, .primary), (caption.coming, .secondary.opacity(0.5))]
        var text = AttributedString()
        for (part, color) in parts where !part.isEmpty {
            if !text.characters.isEmpty { text += AttributedString(" ") }
            var styled = AttributedString(part)
            styled.foregroundColor = color
            text += styled
        }
        return text
    }

    /// The answer's Markdown as one text, so it reads and selects as one: headings bold, list items
    /// with their marks, code in a fixed-width font. Inline marks render as bold, italics, code and links.
    private static func formatted(_ markdown: String) -> AttributedString {
        var text = AttributedString()
        for (index, block) in AnswerBlock.blocks(markdown).enumerated() {
            if index > 0 { text += AttributedString(block.isItem ? "\n" : "\n\n") }
            switch block {
            case .paragraph(let line):
                text += inline(line)
            case .heading(let line):
                var heading = inline(line)
                heading.font = .system(size: 15, weight: .semibold)
                text += heading
            case .item(let marker, let line):
                text += AttributedString("\(marker)  ") + inline(line)
            case .code(let code):
                var block = AttributedString(code)
                block.font = .system(size: 13, design: .monospaced)
                block.foregroundColor = .secondary
                text += block
            }
        }
        return text
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private extension AnswerBlock {
    var isItem: Bool {
        if case .item = self { true } else { false }
    }
}

/// A small rounded label in the card's footer.
private struct Chip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
    }
}

/// A key as printed on the keyboard, for shortcut hints.
private struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .rect(cornerRadius: 4))
    }
}

/// Bars that rise from the middle outward with the voice, like an equalizer, and flutter a little so
/// they look alive. Silence is a row of dots.
private struct VoiceBars: View {
    /// How loud the microphone is, from 0 to 1.
    let level: Float
    private static let count = 29
    private static let height: CGFloat = 44
    private static let barWidth: CGFloat = 6

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<Self.count, id: \.self) { index in
                    Capsule()
                        .fill(PanelView.listeningColor)
                        .frame(width: Self.barWidth, height: barHeight(index, at: time))
                }
            }
            .frame(height: Self.height)
        }
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }

    /// Tallest in the middle, falling off toward the ends.
    private func barHeight(_ index: Int, at time: TimeInterval) -> CGFloat {
        let middle = Double(Self.count - 1) / 2
        let distance = abs(Double(index) - middle) / middle
        let shape = exp(-distance * distance * 2.2)
        let flutter = 0.75 + 0.25 * sin(time * 13 + Double(index) * 1.7)
        return max(Self.barWidth, Self.height * CGFloat(Double(level) * shape * flutter))
    }
}

/// A blue edge and halo around the pill that slowly brighten and fade while it listens.
private struct BreathingHalo: View {
    var body: some View {
        TimelineView(.animation) { context in
            let breath = (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.1) + 1) / 2
            ZStack {
                Capsule()
                    .stroke(PanelView.listeningColor, lineWidth: 6 + 4 * breath)
                    .blur(radius: 6 + 5 * breath)
                    .opacity(0.5 + 0.4 * breath)
                Capsule()
                    .strokeBorder(PanelView.listeningColor.opacity(0.75 + 0.25 * breath), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
