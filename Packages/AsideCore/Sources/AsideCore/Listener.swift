/// One stretch of listening, from the talk hotkey to the press that sends.
/// `SpeechListener` is the real one; tests use a fake.
public protocol Listener: AnyObject, Sendable {
    /// What happens while listening, in order. Ends after `finish()` once the last words are final,
    /// after `cancel()`, or with an error that says why listening failed.
    var events: AsyncThrowingStream<ListenerEvent, any Error> { get }
    /// Stops taking audio and finalizes what was heard.
    func finish()
    /// Stops at once. What was heard is dropped.
    func cancel()
}

public enum ListenerEvent: Equatable, Sendable {
    /// Not listening yet, and why: "Downloading the speech model…".
    case preparing(String)
    /// The microphone is on.
    case listening
    /// Everything heard so far. Words at the end may still change until they are final.
    case heard(String)
}
