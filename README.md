# SPEXT

<img src="assets/branding/spext-logo.png" alt="SPEXT" width="560">

[Deutsch](README.de.md) | **English**

SPEXT is a small macOS menu bar app for dictation. Hold a hotkey, speak, release: your speech is transcribed by OpenAI and pasted into the app you are working in. A second hotkey starts a "polish" mode that turns a rambling dictation into a clean, well-structured message.

## Features

- Two global hotkeys: plain dictation and message mode (polish)
- Transcription with OpenAI `gpt-transcribe`, rewriting in message mode with `gpt-6.1-sol`
- Text is pasted directly into the active app, followed by a space so you can keep typing
- Dictionary for names and technical terms that are often misrecognized
- Language setting: German, English or automatic detection
- Interface in English and German, following the macOS system language
- Floating recording indicator with a live waveform and a notice when no speech signal is detected
- Recordings without speech are discarded instead of being sent, which avoids invented "transcripts" of silence
- Reliable handling of AirPods and iPhone (Continuity) microphones, with optional automatic AirPods preference
- Optionally mutes system audio while recording
- Recordings up to 10 minutes
- Local spoken-to-written replacement rules for exact terminology
- Previous clipboard restored after automatic paste, without replacing newer user copies
- Context-aware boundary spacing and punctuation in supported text fields

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with Apple Silicon
- Your own OpenAI API key. Transcription and rewriting are billed by OpenAI per use; see [OpenAI pricing](https://openai.com/api/pricing/).

## Installation

1. Download the latest ZIP from [GitHub Releases](https://github.com/zoblon/SPEXT/releases/latest).
2. Unzip it and move `SPEXT.app` to your Applications folder.
3. Version 1.0.26 is ad hoc signed (no Apple developer certificate) and is not notarized. macOS may block the first launch, and an update from a developer-signed version may require granting permissions again. Right-click the app and choose **Open**, or go to **System Settings > Privacy & Security** and click **Open Anyway**.
4. Enter your OpenAI API key in the settings.
5. Grant the permissions SPEXT asks for. On launch, SPEXT checks them and shows a setup window if anything is missing:
   - **Microphone**: to record your voice.
   - **Input Monitoring**: to detect the global hotkeys while another app is in front.
   - **Accessibility**: to paste the text into the active app by simulating ⌘V.

macOS does not let apps enable these permissions themselves. SPEXT can only trigger the system prompts and open the matching panes in System Settings.

## Usage

The interface is available in English and German and follows your macOS system language. The dictation language (German, English or automatic) is a separate setting and does not depend on the interface language.

| Hotkey (default) | Mode |
|---|---|
| right Option + right Command | Dictation: your words are pasted as spoken |
| right Control + right Option | Message: your dictation is rewritten into a clean message, then pasted |

- Hold the hotkey while you speak and release it when you are done. SPEXT then transcribes the recording and pastes the text.
- Both hotkeys can be changed in the settings.
- Add words to the dictionary in the settings to improve recognition of names, brands and technical terms.
- Set the language to German or English if you always dictate in one language; use automatic detection if you switch.
- The last text is also available in the menu bar popover, so you can copy it again. If the active app changes before pasting, SPEXT does not paste into the wrong window; the text stays on the clipboard.

## Privacy

- Audio and text are sent to OpenAI's API using your own API key. OpenAI's data usage policies apply.
- Your API key is stored in the macOS Keychain and is never logged.
- SPEXT has no telemetry and no analytics, and does not contact any server other than OpenAI's API.
- Recordings and transcripts are not stored. Temporary audio files are deleted after processing. Only settings such as hotkeys, language, microphone and dictionary are stored locally.

See [PRIVACY.md](PRIVACY.md) for details.

## Building from source

1. Open `SPEXT.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, select your own development team.
3. Build and run the `SPEXT` scheme.

Permissions such as Input Monitoring and Accessibility are tied to the app's signature. If you run a build with a different signature, you may need to grant them again.

The guard tests run without Xcode's test runner:

```sh
sh SPEXTTests/run-guard-tests.sh
```

## Development

Architecture, implementation details and known limitations are documented in [CLAUDE.md](CLAUDE.md) (identical to [AGENTS.md](AGENTS.md)). Model evaluations are in [docs/](docs/).

## Acknowledgements

The idea for SPEXT comes from the open-source app [blitztext](https://github.com/cmagnussen/blitztext-app) by cmagnussen. SPEXT is an independent implementation.

## License and trademarks

MIT License, see [LICENSE](LICENSE).

SPEXT is an independent project and not affiliated with OpenAI or Apple. OpenAI is a trademark of OpenAI; macOS and AirPods are trademarks of Apple Inc.


## Brand assets

The logo, app icon, menu-bar template, social preview and their sources are in [assets/branding](assets/branding).

## Replacement rules and insertion

In **Settings → Dictionary → Replacement rules**, add a spoken form and the written form you want. Rules run locally after recognition, before rewriting or insertion. In message mode, the model may subsequently change wording again. Matching uses whole terms, ignores case and tolerates whitespace differences. The longest overlapping term wins; replacements do not cascade. Empty or ambiguous rules are not applied. If substitutions changed a transcript, the popover also lets you copy its original recognized text.

Automatic paste temporarily preserves the previous clipboard and restores it after a bounded read/quiet wait while SPEXT owns it. A newer user copy wins. The last text remains available in the popover. Supported fields supply local cursor context for spacing and isolated duplicate boundary punctuation; unavailable context keeps the previous trailing-space behavior. Field context is never sent to OpenAI. Posting Cmd+V does not independently confirm that every target app accepted the text.

### Permission troubleshooting

If macOS shows SPEXT enabled but the app still reports missing access, open the recovery guide in setup or Settings → Access. It displays the running app’s version and location. Keep one copy in Applications, remove stale SPEXT entries from Input Monitoring and Accessibility, add that same copy again and restart it. The app never changes grants on your behalf. Ad-hoc signed builds can require renewed consent after updates.
