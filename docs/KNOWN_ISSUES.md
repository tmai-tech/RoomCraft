# Known issues — RoomCraft closed beta

Last updated: 2026-07-13 · Version **1.0.0-beta.1+5**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| Free accurate scan is a **measured layout sketch** | Not LiDAR / full CV walls from photo geometry | Enter exact Width × Length (source of truth); edit openings in blueprint |
| Furniture from photos needs free vision key in the **build** | Without `ROOMCRAFT_GROQ_API_KEY` secret, furniture list is empty | Add pieces from catalog — room size stays exact either way |
| Optional personal Groq/Gemini keys | Only if you want your own quota | Leave blank — free scan works without them; keys stored securely on device |
| Gemini quota (optional mode) | Cloud AI may fail | Prefer Free accurate scan |
| No cloud sync | Plans stay on one device | Export PNG to share |
| Android-first | iOS not in beta | Use Android tester build |
| Debug APK size large | ~100MB+ | Normal for debug Flutter builds |
| Small furniture catalog | Only common types | Custom sizes available when adding |

## How to report

1. In app: **Settings → Send feedback**
2. Or GitHub issues: https://github.com/tmai-tech/RoomCraft/issues
