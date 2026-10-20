# SPEXT brand assets

Tobi accepted logo draft 10 and requested app/repository integration on 2026-10-19. These files replace the historical material under `drafts/`.

| Asset | Use |
|---|---|
| `spext-logo.png` | Transparent, tightly cropped wordmark; README and layouts |
| `spext-logo.svg` | Hybrid master at the original canvas size |
| `spext-logo-dark.png`, `.svg` | Lighter blue-violet lettering for small uses on dark surfaces |
| `spext-app-icon.png` | 1024×1024 app icon; flat blue-violet tile and centered approved bolt |
| `spext-menubar.png`, `@2x`, `@3x` | 18/36/54 px monochrome template; macOS and app-state tinting |
| `spext-wordmark.png`, `@2x`, `@3x` | Popover header exports |
| `spext-social-preview.png` | English GitHub preview, 1280×640 |
| `sources/` | Selected V10 masters, original generated V6 lettering source, construction and draft checks |
| `manifest.json` | Export dimensions and SHA-256 hashes, including Xcode catalog copies |

## Design and origin

V11 color refinement and quieter application design (accepted by Tobi on 2026-10-20): blue-violet `#696BC8` → `#555AB6`, lime `#C9EF67`, and warm paper `#F5F3EE`. The narrow blue-violet range and softer lime reduce the previous pink/electric appearance. The app uses the same restrained accent with warm adaptive neutral surfaces. Contours stay close to the fill colors; no green letter accents, bevel, glow or shadow. The V10 bolt is the recognizable V7 contour, made taller in V9 and 25% wider in V10. App icon and menu-bar template use that literal outline, not a separately generated interpretation. Letter and bolt geometry is unchanged in V11. Historical V10 masters remain in `sources/`; current color masters are versioned as V11.

The lettering originated with built-in Codex image generation in V6. Its selected alpha silhouettes are preserved; colors were replaced deterministically. The SVG contains embedded raster masks for the letters and a native vector bolt. It is **not a full-vector wordmark or an installable font**. The original V6 PNG and V10 construction files are preserved in `sources/`. The approval-pending statuses inside the archived construction/verification source files describe the original draft checks; the acceptance above and export manifest record the later approval. Older prompts and drafts remain under `drafts/`; they are historical, not production instructions.

## Re-export and verify

With Python 3 and Pillow installed, run `python3 scripts/export-branding.py`. The script consumes the approved PNG masters and preserves typography/bolt geometry. Supporting social-preview text uses Arial on macOS; set `SPEXT_FONT_REGULAR` and `SPEXT_FONT_BOLD` to equivalent font files on another system. The two native source SVGs for the app tile and menu template can be rasterized separately with an SVG renderer when those masters are intentionally changed.

Run `python3 scripts/verify-branding.py` to check export hashes, dimensions, app-icon slots and template metadata. Review the result visually before publishing changed graphics. The social-preview PNG must also be uploaded to GitHub repository settings; committing it alone does not change that setting.

The menu-bar asset is a template so the existing red/blue/orange state colors remain functional. The original SF Symbol pulse is replaced with an opacity pulse suitable for a custom image. `SPEXTWordmark` includes a native dark-appearance variant, derived from the same geometry and alpha masks, to keep small lettering readable.
