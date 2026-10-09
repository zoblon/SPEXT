# SPEXT

[Deutsch](README.de.md) | **English**

SPEXT is a small macOS menu bar app for dictation. Hold a hotkey, speak, release: your speech is transcribed by OpenAI and pasted into the app you are working in. A second hotkey starts a "polish" mode that turns a rambling dictation into a clean, well-structured message.

## Features

- Two global hotkeys: plain dictation and message mode (polish)
- Transcription with OpenAI `gpt-transcribe`, rewriting in message mode with `gpt-6.1-sol`
- Text is pasted directly into the active app, followed by a space so you can keep typing
- Dictionary for names and technical terms that are often misrecognized
- Language setting: German, English or automatic detection
- Floating recording indicator with a live waveform and a notice when no speech signal is detected
- Recordings without speech are discarded instead of being sent, which avoids invented "transcripts" of silence
- Reliable handling of AirPods and iPhone (Continuity) microphones, with optional automatic AirPods preference
- Optionally mutes system audio while recording
- Recordings up to 10 minutes

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with Apple Silicon
- Your own OpenAI API key. Transcription and rewriting are billed by OpenAI per use; see [OpenAI pricing](https://openai.com/api/pricing/).

## Installation

1. Download the latest ZIP from [GitHub Releases](https://github.com/zoblon/SPEXT/releases/latest).
2. Unzip it and move `SPEXT.app` to your Applications folder.
3. The app is signed but not notarized by Apple, so macOS will block the first launch. Right-click the app and choose **Open**, or go to **System Settings > Privacy & Security** and click **Open Anyway**.
4. Enter your OpenAI API key in the settings.
5. Grant the permissions SPEXT asks for. On launch, SPEXT checks them and shows a setup window if anything is missing:
   - **Microphone**: to record your voice.
   - **Input Monitoring**: to detect the global hotkeys while another app is in front.
   - **Accessibility**: to paste the text into the active app by simulating ⌘V.

macOS does not let apps enable these permissions themselves. SPEXT can only trigger the system prompts and open the matching panes in System Settings.

## Usage

The user interface is currently in German. An English localization is in progress.

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
