import Foundation

/// Batches a stream of text deltas into roughly one update per frame.
///
/// Text arrives as hundreds of small deltas, and every change to the displayed
/// string redraws the card: the entire accumulated text is re-parsed as
/// markdown, the transcript is scrolled, and the window is resized to fit.
/// Doing that per token makes the cost quadratic in the answer's length —
/// which is why long answers used to grow visibly janky as they arrived.
/// Batching to roughly one update per frame is invisible to a reader and
/// makes it linear.
///
/// Extracted from Gloss's `AnswerModel`, which held one of these for the
/// answer and one for the model's reasoning. The owner keeps the accumulated
/// text; this only decides WHEN the pending tail is handed over.
@MainActor
public final class DeltaBuffer {
    /// Short enough to read as streaming, long enough to coalesce a burst.
    nonisolated public static let defaultInterval: TimeInterval = 0.05

    private var pending = ""
    private var timer: DispatchWorkItem?
    private let interval: TimeInterval
    private let sink: (String) -> Void

    /// `sink` receives everything buffered since the last flush, on the main
    /// actor, either when the timer fires or when `flush()` is called.
    public init(interval: TimeInterval = DeltaBuffer.defaultInterval, sink: @escaping (String) -> Void) {
        self.interval = interval
        self.sink = sink
    }

    public func append(_ delta: String) {
        pending += delta
        schedule()
    }

    /// Hands over everything buffered right now. Must be called before
    /// anything reads the finished text — otherwise the last few tokens are
    /// still pending when the answer is declared done, copied, or written to
    /// history.
    public func flush() {
        timer?.cancel()
        timer = nil
        guard !pending.isEmpty else { return }
        let text = pending
        pending = ""
        sink(text)
    }

    /// Drops whatever is buffered without delivering it. A rerun starts from
    /// nothing; text from the run being replaced would otherwise appear at
    /// the head of the new answer.
    public func discard() {
        timer?.cancel()
        timer = nil
        pending = ""
    }

    private func schedule() {
        guard timer == nil else { return } // one already pending
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }
}
