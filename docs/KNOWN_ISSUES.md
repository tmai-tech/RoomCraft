# Known issues — RoomCraft closed beta

Last updated: 2026-07-24 · Version **1.0.0-beta.1+134**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| **Gallery photos ≠ metric 100%** | Monocular AI cannot measure real feet like LiDAR | Use **Home → Home Scan / AR Room Planner** (easy walk +128) for locked room size |
| **AR walk needs full wall loop** | Partial walk under-sizes room | +126/+128: walk until cover high; pose trail helps incomplete floor mesh |
| **AR measure needs floor planes** | Pins do nothing until tracking + floor detected | Wait for live camera / floor grid; update Play Services for AR if black |
| Photo/AI wall scan is **assistive only** | Doors/furniture often wrong without tape | Prefer AR measure or Field measure; edit openings on Review |
| Furniture still empty after AR size-only | AR locks metric size first (Planner5D-class) | +128 seeds placeholder door/window; add furniture from catalog / AR Place / photos |
| Scan confidence is **heuristic** on photos | Photo score is not survey-grade | AR walk plan can show **100% measured geometry** when cover tight |
| Video keyframes depend on device codecs | Some videos yield few frames | Prefer mid-length 10–30s, good light; or still photos |
| Vision may miss small/occluded items | Incomplete furniture/openings | Add from catalog / draw doors / live AR place |
| Cloud Sign-In needs Firebase setup | Backup may fail until console steps done | See [PLAY_AND_SIGNING.md](PLAY_AND_SIGNING.md): add CI SHA-1, enable Google provider, refresh `google-services.json`, set web client id |

## How to report

1. Settings → Send feedback  
2. https://github.com/tmai-tech/RoomCraft/issues
