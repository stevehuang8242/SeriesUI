import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SeriesUI

/// A menu-bar panel has no Edit menu to dispatch ⌘A/⌘C/⌘V/⌘X/⌘Z, so it matches them by
/// hand — and a hand-rolled match is only as good as the layouts it was tried
/// on. It was tried on one: under 注音 the C key reports "ㄏ", nothing matched,
/// and an answer could not be copied at all. These cover both readings of a
/// key event, and the modifier combinations that must stay other people's.
final class EditingShortcutsTests: XCTestCase {
    /// A ⌘-something, described the way the two layouts describe it: what the
    /// key printed, and which key it physically was.
    private func event(
        characters: String, keyCode: Int, flags: NSEvent.ModifierFlags = .command
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    // MARK: The latin reading

    func testCommandCCopies() {
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "c", keyCode: kVK_ANSI_C)), "copy:")
    }

    func testTheOtherFourAreMatched() {
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "a", keyCode: kVK_ANSI_A)), "selectAll:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "v", keyCode: kVK_ANSI_V)), "paste:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "x", keyCode: kVK_ANSI_X)), "cut:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "z", keyCode: kVK_ANSI_Z)), "undo:")
    }

    func testShiftZRedoes() {
        let redo = event(characters: "z", keyCode: kVK_ANSI_Z, flags: [.command, .shift])
        XCTAssertEqual(EditingShortcuts.action(for: redo), "redo:")
    }

    /// An uppercase character is what a ⌘⇧ combination reports.
    func testTheCharacterIsReadCaseInsensitively() {
        let event = event(characters: "C", keyCode: kVK_ANSI_C, flags: [.command, .shift])
        XCTAssertEqual(EditingShortcuts.action(for: event), "copy:")
    }

    // MARK: The non-latin reading — the bug

    /// 注音, Japanese, Korean, Cyrillic: the character says nothing about
    /// which shortcut this is, and the physical key says everything.
    func testCommandCCopiesUnderABopomofoLayout() {
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "ㄏ", keyCode: kVK_ANSI_C)), "copy:")
    }

    func testTheOtherFourAreMatchedUnderABopomofoLayout() {
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "ㄇ", keyCode: kVK_ANSI_A)), "selectAll:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "ㄍ", keyCode: kVK_ANSI_V)), "paste:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "ㄨ", keyCode: kVK_ANSI_X)), "cut:")
        XCTAssertEqual(EditingShortcuts.action(for: event(characters: "ㄈ", keyCode: kVK_ANSI_Z)), "undo:")
    }

    /// The fallback is by physical key, so it must not answer for keys that
    /// are not one of the five.
    func testAnUnrelatedKeyIsNotClaimedUnderABopomofoLayout() {
        XCTAssertNil(EditingShortcuts.action(for: event(characters: "ㄒ", keyCode: kVK_ANSI_B)))
    }

    // MARK: What stays someone else's

    func testWithoutCommandNothingIsClaimed() {
        XCTAssertNil(EditingShortcuts.action(for: event(characters: "c", keyCode: kVK_ANSI_C, flags: [])))
    }

    /// ⌃C and ⌥C are other shortcuts entirely — swallowing them would take
    /// them away from whatever is focused.
    func testOtherModifiersAreNotClaimed() {
        let control = event(characters: "c", keyCode: kVK_ANSI_C, flags: [.command, .control])
        let option = event(characters: "c", keyCode: kVK_ANSI_C, flags: [.command, .option])
        XCTAssertNil(EditingShortcuts.action(for: control))
        XCTAssertNil(EditingShortcuts.action(for: option))
    }
}
