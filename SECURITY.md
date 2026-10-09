# Security policy

SPEXT records audio, reads global hotkeys and pastes text into other apps, and it stores an OpenAI API key. Security reports are welcome.

## Reporting a vulnerability

Please report security problems privately via [GitHub security advisories](https://github.com/zoblon/SPEXT/security/advisories/new), not as a public issue. Never include your API key or private dictation content.

This is a one-person project, so there is no fixed response time.

## Especially relevant

- the API key leaving the macOS Keychain or ending up in logs,
- audio or text being sent anywhere other than OpenAI's API,
- text being pasted into a different app than the one that was active when recording started,
- recordings or transcripts persisting on disk after processing.

## Supported versions

Only the latest release receives fixes.
