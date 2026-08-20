import AppKit
import Carbon.HIToolbox

// MARK: - Editing shortcuts without an Edit menu

/// ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z (and ⇧⌘Z) for a panel that has no Edit menu.
///
/// AppKit dispatches those shortcuts through the MAIN MENU's key
/// equivalents — and a menu-bar agent whose only menu hangs off the status
/// item has no Edit menu, so none of them ever reached a focused field.
/// (Typing worked; select-all silently did nothing.) Rather than grow a full
/// menu bar for five shortcuts, a panel's key monitor hands the event here and
/// it goes straight down the responder chain.
///
/// Moved here from Gloss. Minute has a real menu bar, but its custom overlays
/// and floating panels hit the same wall.
@MainActor
public enum EditingShortcuts {
    /// True when the event was handled and the caller should swallow it.
    public static func handle(_ event: NSEvent) -> Bool {
        guard let name = action(for: event) else { return false }
        return NSApp.sendAction(Selector(name), to: nil, from: nil)
    }

    /// The selector an event is asking for, or nil if it isn't one of the five.
    ///
    /// Named rather than built with #selector: undo:/redo: live on
    /// UndoManager's client protocol, not on a type we can name here, and the
    /// editing four are only reachable through NSText/NSResponder overloads
    /// that #selector can't disambiguate.
    nonisolated public static func action(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control), !flags.contains(.option),
              let key = letter(for: event)
        else { return nil }
        switch key {
        case "a": return "selectAll:"
        case "c": return "copy:"
        case "v": return "paste:"
        case "x": return "cut:"
        case "z": return flags.contains(.shift) ? "redo:" : "undo:"
        default: return nil
        }
    }

    /// Which of the five keys was pressed — read from the CHARACTER while the
    /// layout has a latin one to give, and from the physical key when it
    /// doesn't.
    ///
    /// Under a non-latin input source the character is no help: with 注音
    /// selected the C key reports "ㄏ", so a character comparison alone
    /// matched nothing and the whole of this file's reason for existing
    /// stopped working — ⌘C on an answer did nothing at all. AppKit's own
    /// menu matching falls back to an ASCII-capable layout for exactly this;
    /// this path stands in for the menu, so it has to fall back too. Layouts
    /// that ARE latin (Dvorak, AZERTY) never reach the fallback, which is
    /// what keeps their shortcuts on the keys they print rather than on
    /// QWERTY's positions.
    private nonisolated static func letter(for event: NSEvent) -> Character? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(),
           typed.count == 1, let character = typed.first,
           character.isASCII, character.isLetter {
            return character
        }
        switch Int(event.keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Z: return "z"
        default: return nil
        }
    }
}

// MARK: - Line break in a field that sends on Return

/// ⇧↩ breaks the line instead of sending it.
///
/// A chat input sends on Return, which is the convention and stays. But a
/// question worth two sentences then had no way to break a line at all.
/// AppKit's own line-break key in a field like this is ⌥↩ — which works
/// today, and which nobody knows — while every chat box the reader already
/// types in puts it on ⇧↩. SwiftUI hands ⇧↩ to the field as a plain submit,
/// so a panel's key monitor has to tell the two apart before it gets there.
@MainActor
public enum NewlineKey {
    /// True when the event was handled and the caller should swallow it.
    public static func handle(_ event: NSEvent, in window: NSWindow?) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == UInt16(kVK_Return),
              flags.contains(.shift),
              // ⌘↩ is the picker's "ask this as a question", and ⌥↩ already
              // breaks the line by itself. Neither is ours to take.
              !flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
              let editor = window?.firstResponder as? NSTextView,
              // The answer body is a text view too, and clicking into it to
              // quote a line makes it the first responder. Only something
              // being TYPED into has a line to break.
              editor.isEditable,
              // Marked text belongs to the input method: mid-注音 this Return
              // confirms the candidate, and taking it would eat the word.
              !editor.hasMarkedText()
        else { return false }
        // Ignoring the field editor is the whole point: `insertNewline:` is
        // exactly what a one-line-ish field turns into a send.
        editor.insertNewlineIgnoringFieldEditor(nil)
        return true
    }
}
