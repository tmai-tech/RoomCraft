# Known issues — RoomCraft closed beta

Last updated: 2026-07-11 · Version **1.0.0-beta.1**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| Free offline scan draws a rectangle | Not full CV walls from photo geometry | Enter exact Width × Length; edit openings in blueprint |
| Free AI (Groq) needs free API key | Furniture detection needs console.groq.com key | Use offline empty plan, or add key in Settings |
| Gemini quota (optional mode) | Cloud AI may fail | Prefer Free offline or Free AI (Groq) |
| Collision uses expanded AABB | Rare false positives when rotated | Nudge items manually |
| No cloud sync | Plans stay on one device | Export PNG to share |
| Android-first | iOS not in beta | Use Android tester build |
| Debug APK size large | ~100MB+ | Normal for debug Flutter builds |

## How to report

1. In app: **Settings → Send feedback**
2. Or GitHub issues: https://github.com/tmai-tech/RoomCraft/issues
