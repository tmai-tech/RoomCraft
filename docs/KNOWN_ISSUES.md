# Known issues — RoomCraft closed beta

Last updated: 2026-07-23 · Version **1.0.0-beta.1+120**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| **Gallery photos ≠ metric 100%** | Monocular AI cannot measure real feet like LiDAR | Use **Home → AR Room Planner** (4-wall AR chain) for locked room size (+119+) |
| **AR measure needs floor planes** | Mark does nothing until tracking + floor detected | +120: wait for “Tracking · floor plane(s)”, good light, move slowly; do not install +119 if camera was flipping |
| Photo/AI wall scan is **assistive only** | Doors/furniture often wrong without tape | Prefer AR measure or Field measure; edit openings on Review |
| Furniture list empty after scan | Model returned [] or filter dropped items | AR Place / catalogue after measure; HF Qwen fallback on photo path |
| Scan confidence is **heuristic** on photos | Photo score is not survey-grade | AR chain empty plan can show **100% measured geometry**; tape/AR floors |
| Video keyframes depend on device codecs | Some videos yield few frames | Prefer mid-length 10–30s, good light; or still photos |
| Vision may miss small/occluded items | Incomplete furniture/openings | Add from catalog / draw doors / live AR place |
| Cloud Sign-In needs Firebase setup | Backup may fail until console steps done | See [PLAY_AND_SIGNING.md](PLAY_AND_SIGNING.md): add CI SHA-1, enable Google provider, refresh `google-services.json`, set web client id |

## How to report

1. Settings → Send feedback  
2. https://github.com/tmai-tech/RoomCraft/issues
