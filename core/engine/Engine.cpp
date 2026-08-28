//
//  Engine.cpp — hardened 84Key overlay around the imported OpenKey engine.
//
//  Keep the large upstream-derived implementation byte-for-byte in
//  EngineUpstream.inc. This tiny translation-unit wrapper makes fork-specific
//  boundary policy reviewable without burying it inside ~2,000 lines of legacy
//  engine code.
//
//  Telex uses letters for modifiers, so an ASCII digit is a natural token
//  boundary. Treating a mid-token digit as part of the Telex word poisoned the
//  raw English detector: a compound such as "dashboard" could carry a temporary
//  Vietnamese mark, then the following "1" made buildEngRawFromStates() reject
//  the whole token before the boundary restore ran. Result: "dashboard1" could
//  be left accented. VNI is intentionally excluded because digits 1–9 are its
//  actual tone/modifier keys.
//

// Compile the imported implementation under a private entry-point name. All of
// its file-static state/helpers remain in this translation unit, so the wrapper
// can apply one narrowly scoped policy and then delegate every other keystroke
// unchanged.
#define vKeyHandleEvent vKeyHandleEventUpstream
#include "EngineUpstream.inc"
#undef vKeyHandleEvent

void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus,
                     const bool& otherControlKey) {
    // The upstream engine already has a fully tested number-boundary path for a
    // shifted number. Reuse that exact path for an unshifted mid-word number in
    // Telex-style modes by presenting only the engine with a synthetic Shift
    // state. The physical event is untouched: the macOS host still emits the
    // actual digit, and tests pass the actual literal trigger character.
    const bool telexDigitBoundary =
        event == vKeyEvent::Keyboard &&
        state == vKeyEventState::KeyDown &&
        IS_NUMBER_KEY(data) &&
        capsStatus == 0 &&
        vInputType != vVNI &&
        _index > 0;

    const Uint8 engineCapsStatus = telexDigitBoundary ? 1 : capsStatus;
    vKeyHandleEventUpstream(event, state, data, engineCapsStatus, otherControlKey);

    if (!telexDigitBoundary)
        return;

    // The synthetic Shift exists only to select the upstream boundary branch.
    // Remove its bookkeeping bit from history so Backspace/macro history still
    // describes the physical unshifted digit rather than !/@/#/... .
    _isCaps = false;
    if (!_specialChar.empty() &&
        (Uint16)(_specialChar.back() & CHAR_MASK) == data) {
        _specialChar.back() &= ~CAPS_MASK;
    }
    if (vUseMacro && !hMacroKey.empty() &&
        (Uint16)(hMacroKey.back() & CHAR_MASK) == data) {
        hMacroKey.back() &= ~CAPS_MASK;
    }
}
