# SPEXT brand handoff — 2026-10-09

**Status: paused at Tobi's request. Design approval is pending.**
This handoff and its draft assets are being uploaded so work can continue on another Mac. No new branding has been integrated into the running app, the Xcode asset catalog, release packages, or GitHub's social-preview setting.

## Resume here

Read this document, then inspect [draft 2 review](../../assets/branding/drafts/spext-review-v2.png) and [wordmark draft 2](../../assets/branding/drafts/spext-logo-v2.png). Use draft 2 as the controlling reference. The next image-generation prompt is saved in [next-logo-edit-prompt.txt](../../assets/branding/drafts/next-logo-edit-prompt.txt). **It has not been executed.** Wait for Tobi to ask to resume. An explicit continuation request authorizes new review drafts; do not ask him to authorize that same step again. Production integration still requires design approval.

## Brief and latest decisions

SPEXT needs a wordmark, macOS app icon, menu-bar icon, and GitHub social preview. The identity should feel modern and dynamic and suggest faster text entry / saved typing time. No measured time-saving claim is available.

- Purple/lilac wordmark; neon green belongs to the lightning bolt.
- Draft 1 lettering was too generic. Tobi called draft 2 significantly better. Retain its custom letterforms, oblique terminals and rounded zigzag vocabulary.
- No green accents on letters. The proposed accent on T was explicitly rejected.
- Neon green is too low-contrast on white. Tobi's latest direction is a **very narrow dark-green contour around the neon-green bolt**, visually unobtrusive and helpful on light backgrounds.
- The earlier purple contour looked bad and is rejected.
- Chrome was briefly explored, then superseded by the dark-green-contour direction.
- **Keep everything flat.** Tobi explicitly said: »Bitte nicht plastisch werden.« No chrome, bevel, extrusion, shine, glow or shadow.
- App-icon bolt must be centered. This is still open.
- Update app/repo branding and publish a new app package only after Tobi approves the finished asset set. Uploading this handoff is not design approval.

## Asset inventory and honest status

All files are under [assets/branding/drafts](../../assets/branding/drafts).

| File | Status / use |
|---|---|
| spext-logo-source-v2.png | Unmodified generated source, 2172 × 724 RGBA. |
| spext-logo-v2.png | Transparent, trimmed draft-2 wordmark; controlling reference, 2083 × 484. Still has the original unoutlined lime bolt. |
| spext-logo-source-v1.png | Earlier typography, retained for history; do not resume from it. |
| spext-app-icon-source-v1.png | Original icon, 1254 × 1254 RGBA; bolt is too far right/down. |
| spext-app-icon-v1.png | 1024 × 1024 export of that original; not a corrected icon. |
| spext-app-icon-source-v2.png | Two centering edits attempted. Improved, but still not centered. Not approved. |
| spext-menubar-source-v1.png | Generated single-color bolt source with real alpha. |
| spext-menubar-v1.png / @2x / @3x | 18/36/54 px template exports; require actual app integration and UI verification later. |
| spext-social-preview-v2.png | 1280 × 640 English preview using draft 2; must be updated after bolt treatment is selected. |
| spext-review-v2.png | Review sheet BEFORE the latest contrast/centering corrections, not a final set. |
| app-icon-centering-qc-v2.md | Numeric evidence of the unfinished position correction. |
| *-prompt-v*.txt | Exact generation prompts already used; next-logo-edit-prompt.txt is the new unexecuted prompt. |
| export-review-v2.py | Portable deterministic export/review script; recreates the old v2 set, not the new requested correction. |
| handoff-manifest.json | Current file hashes/dimensions/status for this handoff. |

The rejected purple-contour and chrome candidates are intentionally not provided as continuation references. No flat dark-green-contour candidate exists yet.

## App-icon centering — unresolved

The original icon's tile midpoint is approximately (627.5, 627), while the lime bolt bounding-box midpoint is (635, 653): about 7.5 px right and 26 px down.

The two generative positioning attempts did not preserve geometry exactly. Latest source v2: tile midpoint (626.5, 626); bolt midpoint (623.5, 640), so 3 px left / 14 px down. Bolt color-area centroid is (626.77, 640.45). The generator also slightly changed the tile and bolt dimensions. Do not claim »only moved« or »exactly centered«. Read the QC note for the mask thresholds and exclusive bbox coordinates.

Prefer a controlled layered/vector placement for the final icon if available, retaining the approved bolt geometry and checking both bounding-box centering and optical balance. Do not keep repeating unconstrained generative edits: two attempts were already made in this session.

## Next steps

1. Resume only when Tobi asks. Inspect the controlling draft-2 reference.
2. Test the narrow dark-green contour using the saved next prompt. Keep typography and flat lime fill unchanged.
3. Inspect on white, pale lavender and near-black, also at smaller sizes. A visible improvement is required; a render alone is not proof.
4. Resolve exact/optical app-icon alignment and present the corrected asset set for approval.
5. Update the social preview with the chosen bolt treatment and preserve the English copy below.
6. After explicit approval, integrate sources, exports and metadata into the repo; replace Xcode app-icon assets and add a menu-bar template asset while retaining app-state feedback.
7. Build and check the app, validate package/signature/checksum, publish the release through the repo's documented process, set GitHub social preview, and verify the actual released package. Identify and back up any existing installed app before replacement.

## Exact social-preview copy

- macOS dictation app
- Speech to text. Straight into your app.
- Hold a hotkey. Speak. Release.
- Independent project · github.com/zoblon/SPEXT

Do not add numerical speed/accuracy claims.

## Repo integration context

Repository: https://github.com/zoblon/SPEXT, main branch. On inspection the app is version 1.0.23/build 23, Swift/SwiftUI, macOS 14+, Apple Silicon. Recheck current version before implementation.

- App icon: SPEXT/Assets.xcassets/AppIcon.appiconset/
- Menu-bar label: SPEXT/SPEXTApp.swift currently uses Image(systemName: appState.menuBarIcon).
- SPEXT/AppState.swift: menuBarIcon is bolt.fill; menuBarColor changes for recording/transcribing states. Preserve these functional state cues.
- Current documentation is English with README.de.md; UI is localized English/German.
- Follow AGENTS.md. AGENTS.md and CLAUDE.md must remain equivalent if updated. App version/build must match Xcode build settings.
- Releases: local ZIP plus SHA256.txt under ignored Releases/<version>/; publish through gh release create after version bump/tag. This handoff is not a release and does not bump the version.
- The mandatory live OpenAI model review is for release/model/API work. It was not performed for this draft-only handoff; do it before a later release as documented.
