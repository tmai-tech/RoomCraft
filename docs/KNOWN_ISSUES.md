# Known issues — RoomCraft closed beta

Last updated: 2026-07-14 · Version **1.0.0-beta.1+12**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| **Not LiDAR / mm CAD** | Camera photos cannot measure walls like magicplan LiDAR | Use **Field measure** (tape from left corner); ARCore later |
| Photo/AI wall scan is **assistive only** | Doors/furniture often wrong without tape | Prefer Field measure; multi-gallery every wall; edit on Review |
| Furniture list empty after scan | Model returned [] or filter dropped items | +24: lower conf floor + HF Qwen fallback; still not LiDAR |
| Scan confidence is **heuristic** | Score is not survey-grade | Tape path ≈ high; photo path needs Review edits |
| Video keyframes depend on device codecs | Some videos yield few frames | Prefer mid-length 10–30s, good light; or still photos |
| Vision may miss small/occluded items | Incomplete furniture/openings | Add from catalog / draw doors |
| Cloud Sign-In needs Firebase setup | Backup may fail until console steps done | See [PLAY_AND_SIGNING.md](PLAY_AND_SIGNING.md): add CI SHA-1, enable Google provider, refresh `google-services.json`, set web client id |

## How to report

1. Settings → Send feedback  
2. https://github.com/tmai-tech/RoomCraft/issues
