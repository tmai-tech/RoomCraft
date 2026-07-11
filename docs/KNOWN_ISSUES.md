# Known issues — RoomCraft closed beta

Last updated: 2026-07-11 · Version **1.0.0-beta.1**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| AI dimensions are approximate | Plan may need scale fix | Use **Review → scale calibration** or edit room size |
| AI needs a Gemini API key | Scan blocked without key | Settings → paste key from [AI Studio](https://aistudio.google.com) |
| Collision ignores true rotated OBB | Rare false positives/negatives when rotated | Nudge items manually |
| No cloud sync | Plans stay on one device | Export PNG to share; re-scan if needed |
| Android-first | iOS not shipped in beta | Use Android tester build |
| Debug APK size large | ~100MB+ | Normal for debug Flutter builds |
| Furniture catalog is generic | Not brand-accurate | Resize after add |

## Under investigation

- Gemini model availability by region (fallback list in app)
- Gesture conflicts on very small screens (use **Pan** tool)
- Thumbnail scale if plans were drawn far from origin

## How to report

1. In app: **Settings → Send feedback** (email)
2. Or open a GitHub issue on [tmai-tech/RoomCraft](https://github.com/tmai-tech/RoomCraft/issues)

Please include: device model, Android version, steps, and screenshots.
