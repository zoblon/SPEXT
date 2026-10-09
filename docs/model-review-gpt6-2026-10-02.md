# Model review for rewriting: GPT-5.6 Terra → GPT-6

As of 2026-10-02. Reason: the GPT-6 family has been released. The question was whether the rewriting model should be switched from `gpt-5.6-terra`. Transcription (`gpt-transcribe`) was not part of this comparison.

**Decision:** switch to `gpt-6.1-sol` with `reasoning_effort = low` as of SPEXT 1.0.22 (build 22), after the maintainer's approval.

## Official documentation (checked live)

| Model | Input / cached / output per 1M tokens | Reasoning | Chat Completions |
|---|---|---|---|
| [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) | 2.00 / 0.20 / 12.00 USD | none–max, default medium | ✓ |
| [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol) | 2.00 / 0.10 / 10.00 USD | low–max, default medium (no `none`) | ✓ |
| [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) | 0.10 / 0.01 / 0.50 USD | none–max, default medium | ✓ |

- [GPT-6 guide](https://developers.openai.com/api/docs/guides/latest-model): the family consists of Astra, Sol and Luna; there is no longer a Terra tier. With reasoning other than `none`, `temperature`, `top_p` and `(top_)logprobs` must not be sent. SPEXT sends none of these parameters.
- [Deprecations](https://developers.openai.com/api/docs/deprecations): `gpt-5.6-terra` is not deprecated, so there was no time pressure. `gpt-transcribe` is still the recommended transcription model.
- GPT-6 Astra was not tested. As the largest and most expensive model, it is oversized for short, latency-sensitive rewrites.

## Test setup

- Same request as in the app: `PolishPrompt.systemPrompt` (read directly from `PolishService.swift`), `reasoning_effort = low`, `max_completion_tokens = 4096`, Chat Completions.
- Eight typical dictations (6 × German, 2 × English): short informal message (du), formal message (Sie) with a topic change and a self-correction, enumeration, long messy dictation with uncertainty, meta instruction with proper names, casual English, formal English, short question.
- Two runs per model; the model order was reversed in each round. 48 requests in total, all successful (`finish_reason = stop`).
- Limitation: the dictation texts were synthetic but realistic. Real dictations from transcriptions were not used.

## Results

| | Terra 5.6 | Sol 6.1 | Luna 6 |
|---|---|---|---|
| Latency median / max | **1.71 s** / 3.93 s | 2.79 s / 3.97 s | **1.57 s** / 2.13 s |
| Cost per message (avg. 626 in / ~60 out tokens) | 0.20 cents | 0.19 cents | 0.01 cents |
| Facts preserved (numbers, dates, names, corrections) | ✓ | ✓ | ✓ |
| Language kept | ✓ | ✓ | ✗ English dictation translated into German in **both** runs |
| No invented salutation | ✗ "Sehr geehrte Frau Albers" (Dear Ms. Albers) (2/2) | ✓ | ✗ "Guten Tag Frau Albers" (Good day, Ms. Albers), "Hallo zusammen" (Hi all) |
| Uncertainty preserved ("oder war das Peter?", "or was it Peter?") | ✗ dropped | ✓ in both runs | ✗ dropped |
| Enumeration as a list (prompt: "if the user clearly lists several points") | running text | ✓ list | running text |

Observations:

- **Terra** is fast and linguistically clean, but reproducibly violates the prompt rule "do not invent a salutation". Occasionally Terra phrases a request more sharply than dictated ("Bitte veranlassen Sie die Zahlung", "Please arrange the payment", instead of a friendly reminder).
- **Sol** follows the prompt rules most reliably and reproduces the speaker's uncertainties most faithfully. Sol tends to leave filler questions ("Kannst du mir kurz sagen …", "Can you quickly tell me …") as they are instead of condensing them. In short dictations, numbers are sometimes left spelled out ("zehn Uhr", "ten o'clock"). The price for this is about 1 second more latency in the median.
- **Luna** is very cheap and fast, but translating an English dictation violates a core rule. That rules Luna out for SPEXT. Luna could be re-evaluated with an adjusted prompt (e.g. an English system prompt or an explicit language rule at the beginning).

## Consequences for SPEXT

- `PolishConfiguration.model = "gpt-6.1-sol"`; reasoning `low`, token limit and prompt remain unchanged. The settings display and tests have been updated.
- Timeout (30 s) and retry remain unchanged; the measured maximum latency was below 4 s.
- After the switch, keep an eye on latency and tone in everyday use. If the waiting time becomes annoying, Terra would be the fallback option as long as it is not deprecated.
