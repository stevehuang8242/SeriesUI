import XCTest
@testable import SeriesUI

/// Deltas are batched before they reach the displayed text, which is what
/// stops a long answer from re-parsing itself on every token. The risk that
/// buys is losing the tail: text still sitting in the buffer when something
/// decides the answer is finished, copies it, or writes it to history.
@MainActor
final class DeltaBufferTests: XCTestCase {
    /// A buffer and the string it feeds, the way an answer model holds them.
    @MainActor private final class Sink {
        var text = ""
        lazy var buffer = DeltaBuffer { [unowned self] in self.text += $0 }
    }

    func testDeltasAreHeldUntilFlushed() {
        let sink = Sink()
        sink.buffer.append("Hel")
        sink.buffer.append("lo")
        XCTAssertEqual(sink.text, "", "deltas should batch, not land one by one")

        sink.buffer.flush()
        XCTAssertEqual(sink.text, "Hello")
    }

    /// Order matters more than anything else here — the answer is prose.
    func testManyDeltasKeepTheirOrder() {
        let sink = Sink()
        let pieces = (0..<500).map { "\($0 % 10)" }
        for piece in pieces { sink.buffer.append(piece) }
        sink.buffer.flush()
        XCTAssertEqual(sink.text, pieces.joined())
    }

    func testFlushingTwiceDoesNotDuplicate() {
        let sink = Sink()
        sink.buffer.append("once")
        sink.buffer.flush()
        sink.buffer.flush()
        XCTAssertEqual(sink.text, "once")
    }

    func testAppendingAfterAFlushContinuesTheAnswer() {
        let sink = Sink()
        sink.buffer.append("first ")
        sink.buffer.flush()
        sink.buffer.append("second")
        sink.buffer.flush()
        XCTAssertEqual(sink.text, "first second")
    }

    /// A rerun starts from nothing. Buffered text from the run being replaced
    /// would otherwise appear at the head of the new answer.
    func testDiscardDropsWhateverWasStillBuffered() {
        let sink = Sink()
        sink.buffer.append("from the old run")
        sink.buffer.discard()
        sink.buffer.flush()
        XCTAssertEqual(sink.text, "")
    }

    /// Nothing has to call flush for text to appear: the timer does it, which
    /// is what makes the answer stream rather than arrive in one lump.
    func testBufferedTextLandsOnItsOwnShortly() async throws {
        let sink = Sink()
        sink.buffer.append("streamed")

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sink.text, "streamed")
    }

    /// The batching window has to be short enough to read as streaming.
    func testTheFlushIntervalStaysImperceptible() async throws {
        let sink = Sink()
        sink.buffer.append("x")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(sink.text, "x", "text should be visible well inside a fifth of a second")
    }
}
