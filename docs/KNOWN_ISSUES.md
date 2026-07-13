# Known issues — RoomCraft closed beta

Last updated: 2026-07-13 · Version **1.0.0-beta.1+9**

## Expected limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| **Not LiDAR / mm CAD** | Walls are a measured rectangle + detected openings | Enter exact W×L; edit walls/doors in blueprint |
| Scan confidence is **heuristic** | Score is not survey-grade | Walk every wall with video/photos; refine manually |
| Video keyframes depend on device codecs | Some videos yield few frames | Prefer mid-length 10–30s, good light; or still photos |
| Vision may miss small/occluded items | Incomplete furniture/openings | Add from catalog / draw doors |
| Cloud Sign-In needs Firebase SHA | Backup may fail | Add debug SHA to Firebase Console |

## How to report

1. Settings → Send feedback  
2. https://github.com/tmai-tech/RoomCraft/issues
