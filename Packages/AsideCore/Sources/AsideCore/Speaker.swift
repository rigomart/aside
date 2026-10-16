/// Says sentences aloud, one after another. `SpeechSpeaker` is the real one; tests use a fake.
@MainActor public protocol Speaker: AnyObject {
    /// Says `sentence` once the ones before it have been said, then calls `said`.
    /// `said` is never called for a sentence that `stop()` cut off or dropped.
    func say(_ sentence: String, said: @escaping @MainActor () -> Void)
    /// Stops at once, mid-word, and drops the sentences still waiting.
    func stop()
}
