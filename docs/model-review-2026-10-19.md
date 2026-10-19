# OpenAI release review — 2026-10-19

Scope: documentation/API-contract review for the branding-only 1.0.24 release. No model, prompt or request parameter changes. No new audio benchmark or paid model comparison was performed; the controlled comparison in [the previous review](model-review-gpt6-2026-10-02.md) remains the behavioral evidence.

The official pages below were opened live on 2026-10-19:

- [GPT Transcribe](https://developers.openai.com/api/docs/models/gpt-transcribe): current file-transcription model, documented price $0.0045/minute. [File transcription](https://developers.openai.com/api/docs/guides/speech-to-text) confirms `languages`, `keywords`, `prompt`, JSON output and the `/v1/audio/transcriptions` endpoint. SPEXT already uses this contract.
- [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol): documented text prices $2 input / $10 output per million tokens, $0.10 cached input; `low` reasoning supported. Chat Completions remains supported without tool calling, matching SPEXT's rewriting request.
- [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna): lower-cost alternative ($0.10 input / $0.50 output per million tokens). The previous SPEXT comparison found unwanted translation of English dictations. Lower published cost alone does not establish a quality improvement; do not switch without a new representative German/English comparison.
- [Deprecations](https://developers.openai.com/api/docs/deprecations): legacy Whisper/GPT-4o transcription models are scheduled for shutdown on 2027-02-26, with GPT Transcribe / GPT Live Transcribe as replacements. SPEXT already uses GPT Transcribe. No shutdown of the two currently configured model IDs was found in this review.

Decision: retain `gpt-transcribe` and `gpt-6.1-sol` with `reasoning_effort = low`. GPT Live Transcribe targets streaming and would require an architectural/latency comparison; this release does not change the recording lifecycle. No claim is made that documentation alone proves the configured models are universally optimal.
