# Privacy

SPEXT runs on your Mac. It has no server of its own, no telemetry and no analytics. The author never receives any data.

## What is sent where

- **Audio:** when you release the hotkey, the recording is sent to OpenAI's transcription API (`api.openai.com`) using your own API key. Recordings shorter than one second or without detectable speech are discarded locally and never uploaded.
- **Text:** in message mode, the transcript is additionally sent to OpenAI's chat API to be reworded. Your dictionary words are sent along with each transcription request as keywords.
- OpenAI processes this data under its own API terms and privacy policy. Check them, especially if you dictate confidential content.

## What stays on your Mac

- **API key:** stored in the macOS Keychain, never logged.
- **Recordings:** kept only as temporary files during recording and processing, then deleted.
- **Last transcript:** kept in memory so you can copy it from the menu bar popover; it is not written to disk.
- **Logs:** SPEXT logs technical metadata only (timings, byte and character counts, device class, error codes), never audio, transcripts or the API key.
- **Clipboard:** to paste, SPEXT puts the text on the general clipboard, where it stays like any copied text.

## Permissions

Microphone (recording), Input Monitoring (global hotkeys) and Accessibility (pasting with ⌘V). You can revoke them at any time in System Settings → Privacy & Security.
