import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SeriesUI

/// Return sends — that is the chat convention and it stays. ⇧↩ has to break
/// the line instead, which SwiftUI does not do on its own: it reports the
/// shifted Return to the field as a plain submit, so a follow-up longer than
/// one sentence had nowhere to break.
@MainActor
final class NewlineKeyTests: XCTestCase {
    private var window: NSWindow!
    private var editor: NSTextView!

    override func setUp() {
        super.setUp()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView?.addSubview(editor)
        window.makeFirstResponder(editor)
    }

    private func returnKey(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: UInt16(kVK_Return)
        )!
    }

    func testShiftReturnBreaksTheLine() {
        editor.string = "two"
        editor.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(NewlineKey.handle(returnKey(.shift), in: window))
        XCTAssertEqual(editor.string, "two\n")
    }

    /// The convention it must not touch.
    func testPlainReturnIsLeftAloneToSend() {
        XCTAssertFalse(NewlineKey.handle(returnKey([]), in: window))
        XCTAssertEqual(editor.string, "")
    }

    /// ⌘↩ is the picker's "ask this as a question"; ⌥↩ already breaks the line
    /// on its own. Claiming either would take a working key away.
    func testOtherModifiersKeepTheirOwnMeaning() {
        XCTAssertFalse(NewlineKey.handle(returnKey([.shift, .command]), in: window))
        XCTAssertFalse(NewlineKey.handle(returnKey([.shift, .option]), in: window))
        XCTAssertEqual(editor.string, "")
    }

    /// Mid-注音 the Return confirms the candidate. Taking it would eat the
    /// word being typed.
    func testAnInputMethodKeepsItsOwnReturn() {
        editor.setMarkedText(
            "ㄏ", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        XCTAssertTrue(editor.hasMarkedText(), "precondition: composing")

        XCTAssertFalse(NewlineKey.handle(returnKey(.shift), in: window))
    }

    /// Nothing being typed into: the answer body itself is a text view, and a
    /// ⇧↩ there is not a line break anyone asked for.
    func testAReadOnlyViewIsNotWrittenInto() {
        let answer = AnswerTextView()
        answer.textStorage?.setAttributedString(NSAttributedString(string: "an answer"))
        window.contentView?.addSubview(answer)
        window.makeFirstResponder(answer)

        XCTAssertFalse(NewlineKey.handle(returnKey(.shift), in: window))
        XCTAssertEqual(answer.string, "an answer")
    }
}
