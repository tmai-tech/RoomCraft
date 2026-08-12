# Known issues — RoomCraft closed beta

Last updated: 2026-08-12 · Version **1.0.0-beta.1+149**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| **Gallery photos ≠ metric 100%** | Monocular AI cannot measure real feet like LiDAR | Use **Home → Scan the room** (AR walk) + **one-wall tape** (+145/146) |
| **AR walk needs full wall loop** | Partial walk under-sizes room | Walk until cover % rises; or **I measured one wall** on confirm |
| **AR may still over-size** | 29 ft class rooms without tape (b5fa46b8) | +146 soft-caps confirm; hard block >26 without tape; use **Study gold 20.3×17** |
| **AR measure needs floor planes** | Pins do nothing until tracking + floor detected | Wait for live camera / floor grid; update Play Services for AR if black |
| Photo/AI wall scan is **assistive only** | Doors/furniture often wrong without tape | Prefer AR + **Study gold / Lounge** preset or chips |
| Furniture not auto-detected from AR | AR locks metric size first | Pick **Lounge** or **Study gold** on confirm (+146 checklist) |
| Scan confidence is **heuristic** on photos | Photo score is not survey-grade | AR + user confirm / one-wall calibrate is the metric path |
| Video keyframes depend on device codecs | Some videos yield few frames | Prefer mid-length 10–30s, good light; or still photos |
| Vision may miss small/occluded items | Incomplete furniture/openings | Add from catalog / draw doors / live AR place |
| Cloud Sign-In needs Firebase setup | Backup may fail until console steps done | See [PLAY_AND_SIGNING.md](PLAY_AND_SIGNING.md) |

**Latest feedback:** `c643ffe0` on +146 → fixed +147; no new FB after +147.  
**+148–+149:** Phase 3 clean blueprint (gaps, swings, labels) + north-up editor (N↑).  
**Field retest:** [PHASE0_RETEST_CHECKLIST.md](PHASE0_RETEST_CHECKLIST.md) · **Phases:** [SCAN_ACCURACY_BUILD_PHASES.md](SCAN_ACCURACY_BUILD_PHASES.md)

## How to report

1. Settings → Send feedback  
2. https://github.com/tmai-tech/RoomCraft/issues
