# Known issues — RoomCraft closed beta

Last updated: 2026-07-13 · Version **1.0.0-beta.1+6**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| Free accurate scan is a **measured layout sketch** | Not LiDAR / full CV walls from photo geometry | Enter exact Width × Length; edit openings in blueprint |
| **Furniture from photos needs free vision** | Without Groq/Gemini (bundled CI key or Settings), only room frame appears | Set `ROOMCRAFT_GROQ_API_KEY` on CI, or Settings → free Groq key; or add catalog pieces |
| AI may miss small / occluded furniture | Incomplete list | Toggle include in review; add from catalog |
| No cloud sync | Plans stay on one device | Export PNG to share |
| Android-first | iOS not in beta | Use Android tester build |
| Debug APK size large | ~100MB+ | Normal for debug Flutter builds |

## How to report

1. In app: **Settings → Send feedback**
2. Or GitHub issues: https://github.com/tmai-tech/RoomCraft/issues
