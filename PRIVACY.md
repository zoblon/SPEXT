# Privacy

SPEXT runs on your Mac. It has no server of its own, no telemetry and no analytics. The author never receives any data.

## What is sent where

- **Audio:** when you release the hotkey, the recording is sent to OpenAI's transcription API (`api.openai.com`) using your own API key. Recordings shorter than one second or without detectable speech are discarded locally and never uploaded.
- **Text:** in message mode, the transcript is additionally sent to OpenAI's chat API to be reworded. Your dictionary words are sent along with each transcription request as keywords.
- OpenAI processes this data under its own API terms and privacy policy. Check them, especially if you dictate confidential content.

## What stays on your Mac

- **API key:** stored in the macOS Keychain, never logged.
- **Recordings:** kept only as temporary files during recording and processing, then deleted.
- **Last transcript:** kept in memory so you can copy it from the menu bar popover; it is not written to disk. If a replacement rule changes it, the original recognized text is also kept in memory for copying.
- **Replacement rules:** spoken/written pairs are stored locally as settings. Matching happens on your Mac. In message mode, the resulting corrected transcript is sent to OpenAI for rewriting; the rule list itself is not uploaded.
- **Insertion context:** short text windows around the current cursor/selection are read through Accessibility to fit spaces and punctuation. Password/secure fields are excluded before reading. This context is never uploaded, logged or saved. The normal read is limited to 256 UTF16 units per side; AXValue fallback is allowed only when a field reports at most 4096 units.
- **Logs:** SPEXT logs technical metadata only (timings, byte and character counts, device class, error codes), never audio, transcripts or the API key.
- **Clipboard:** automatic paste temporarily backs up all original representations in memory, then restores them after a bounded read/quiet wait while SPEXT owns the clipboard. A newer user copy is never deliberately overwritten. Unreadable or over-64-MiB clipboards are left untouched and automatic paste is refused. Blocked pastes keep dictated text available for manual copy/paste when possible. Read notifications are only a heuristic; clipboard managers may still read temporary text despite transient/concealed markers. Temporary dictated contents are current-host-only. Explicit Copy buttons replace the clipboard normally and are not automatically undone.

## Permissions

Microphone (recording), Input Monitoring (global hotkeys) and Accessibility (pasting with ⌘V). You can revoke them at any time in System Settings → Privacy & Security.
