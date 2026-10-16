import AVFoundation
import Foundation
import Speech

/// Listens with on-device speech recognition (`SpeechAnalyzer`) in the Mac's language. Audio comes from
/// the microphone, or from a file played in real time as if spoken, which UI tests use.
public final class SpeechListener: Listener {
    public enum Source: Sendable {
        case microphone
        case file(URL)
    }

    private enum Stop: Sendable {
        case finish
        case cancel
        case failed(any Error)
    }

    public let events: AsyncThrowingStream<ListenerEvent, any Error>
    private let stops: AsyncStream<Stop>.Continuation
    private let task: Task<Void, Never>

    public init(source: Source, locale: Locale = .current) {
        let (events, output) = AsyncThrowingStream.makeStream(of: ListenerEvent.self)
        let (stops, stop) = AsyncStream.makeStream(of: Stop.self)
        self.events = events
        self.stops = stop
        task = Task {
            do {
                try await Self.run(source: source, locale: locale, stops: stops, stop: stop, output: output)
                output.finish()
            } catch let error as ListenError {
                output.finish(throwing: error)
            } catch {
                output.finish(throwing: ListenError("Couldn't listen: \(error.localizedDescription)"))
            }
        }
    }

    public func finish() {
        stops.yield(.finish)
    }

    public func cancel() {
        stops.yield(.cancel)
        task.cancel()
    }

    private static func run(
        source: Source, locale: Locale, stops: AsyncStream<Stop>, stop: AsyncStream<Stop>.Continuation,
        output: AsyncThrowingStream<ListenerEvent, any Error>.Continuation
    ) async throws {
        if case .microphone = source { try await requestMicrophone() }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            let language = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            throw ListenError("Speech recognition doesn't support \(language).")
        }
        // Fast results update the words about once a second instead of every four.
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: []
        )
        let installed = await AssetInventory.status(forModules: [transcriber]) == .installed
        Log.voice.info("Speech model for \(supported.identifier, privacy: .public) installed: \(installed)")
        if !installed, let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            output.yield(.preparing("Downloading the speech model…"))
            Log.voice.info("Downloading the speech model for \(supported.identifier, privacy: .public)")
            try await download.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw ListenError("Speech recognition has no audio format for \(supported.identifier).")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()

        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let failed: @Sendable (any Error) -> Void = { stop.yield(.failed($0)) }
        let level: @Sendable (Float) -> Void = { output.yield(.level($0)) }
        let stopAudio = switch source {
        case .microphone: try startMicrophone(format: format, feed: feed, level: level, failed: failed)
        case .file(let url): try startFile(url, format: format, feed: feed, level: level, failed: failed)
        }
        defer { stopAudio() }
        try await analyzer.start(inputSequence: input)
        output.yield(.listening)

        let results = Task {
            do {
                // Each result covers the audio after the last final one, so finals add up.
                var final = ""
                for try await result in transcriber.results {
                    let words = joined(final, String(result.text.characters))
                    if result.isFinal { final = words }
                    output.yield(.heard(words))
                }
            } catch {
                failed(error)
            }
        }

        var reason = Stop.cancel
        for await next in stops {
            reason = next
            break
        }
        stopAudio()
        feed.finish()
        switch reason {
        case .finish:
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            await results.value
        case .cancel:
            results.cancel()
            await analyzer.cancelAndFinishNow()
        case .failed(let error):
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func requestMicrophone() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return
        case .undetermined: if await AVAudioApplication.requestRecordPermission() { return }
        default: break
        }
        throw ListenError("Aside can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
    }

    /// Feeds the microphone to `feed`, and how loud each buffer is to `level`, until the returned closure is called.
    private static func startMicrophone(
        format: AVAudioFormat, feed: AsyncStream<AnalyzerInput>.Continuation, level: @escaping @Sendable (Float) -> Void,
        failed: @escaping @Sendable (any Error) -> Void
    ) throws -> () -> Void {
        let engine = AVAudioEngine()
        let microphone = engine.inputNode.outputFormat(forBus: 0)
        guard microphone.channelCount > 0, microphone.sampleRate > 0 else { throw ListenError("No microphone found.") }
        let converter = try Converter(from: microphone, to: format)
        // About 20 buffers a second at 48 kHz, so the level moves smoothly.
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: microphone) { buffer, _ in
            level(Self.level(of: buffer))
            do {
                feed.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
            } catch {
                failed(error)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw ListenError("Couldn't start the microphone: \(error.localizedDescription)")
        }
        return {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    /// Feeds `url` to `feed` in real time, then silence, as a microphone in a quiet room would,
    /// until the returned closure is called. The analyzer only moves on while audio keeps coming.
    /// How loud each buffer is goes to `level`.
    private static func startFile(
        _ url: URL, format: AVAudioFormat, feed: AsyncStream<AnalyzerInput>.Continuation,
        level: @escaping @Sendable (Float) -> Void, failed: @escaping @Sendable (any Error) -> Void
    ) throws -> () -> Void {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ListenError("Couldn't read the audio file \(url.path): \(error.localizedDescription)")
        }
        let converter = try Converter(from: file.processingFormat, to: format)
        let reader = Task {
            do {
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048) else { return }
                    try file.read(into: buffer)
                    level(Self.level(of: buffer))
                    feed.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
                    try await Task.sleep(for: .seconds(Double(buffer.frameLength) / file.processingFormat.sampleRate))
                }
                let tenth = AVAudioFrameCount(format.sampleRate / 10)
                while true {
                    guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tenth) else { return }
                    silence.frameLength = tenth
                    for channel in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                        memset(channel.mData, 0, Int(channel.mDataByteSize))
                    }
                    feed.yield(AnalyzerInput(buffer: silence))
                    level(0)
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch is CancellationError {
            } catch {
                failed(error)
            }
        }
        return { reader.cancel() }
    }
}

extension SpeechListener {
    /// How loud `buffer` is, from 0 to 1: its first channel's loudness (RMS) from -50 dB, a quiet room,
    /// to -10 dB, speaking up close. A buffer without float samples counts as silence.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let decibels = 10 * log10(max(sum / Float(count), 1e-10))
        return min(max((decibels + 50) / 40, 0), 1)
    }
}

/// `before` and `after` with one space between them, however each one ends or starts.
func joined(_ before: String, _ after: String) -> String {
    [before, after].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
}

/// Converts audio buffers to the format the analyzer wants.
private final class Converter {
    private let converter: AVAudioConverter

    init(from: AVAudioFormat, to: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else {
            throw ListenError("Can't convert audio from \(from) to \(to).")
        }
        // No priming: each buffer converts on its own, without a delay added at the start.
        converter.primeMethod = .none
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw ListenError("Couldn't allocate an audio buffer.")
        }
        // The input block runs synchronously inside `convert`, on this thread, but the SDK marks it
        // `@Sendable`; these two are never touched from anywhere else.
        nonisolated(unsafe) let buffer = buffer
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw ListenError("Couldn't convert audio: \(error?.localizedDescription ?? "unknown error")") }
        return output
    }
}

struct ListenError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
