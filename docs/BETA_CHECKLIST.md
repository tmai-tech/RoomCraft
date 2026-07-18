# Closed beta checklist — RoomCraft

## Before inviting testers

- [x] MVP phases 0–4 on `dev`
- [x] Version `1.0.0-beta.1+103` (AR place, L-shape, heatmap, multi-floor/exterior, 10k catalog)
- [x] Firebase App Distribution wired + green CI distribute
- [x] Tester group `testers` exists
- [x] Stable CI keystore SHA for Google Sign-In (see PLAY_AND_SIGNING.md)
- [x] Add **CI + local SHA-1/256** in Firebase Android app (Management API 2026-07-14)
- [x] Create Firestore DB + deploy rules
- [x] Enable Authentication → Get started → Google
- [x] Re-download `google-services.json` (oauth_client populated) + commit
- [x] Set `ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID` secret; rebuild APK (+13)
- [ ] Add tester emails in [Firebase console](https://console.firebase.google.com/project/roomcraft-e1312/appdistribution)
- [ ] Confirm latest successful **Build APK** + distribute run
- [ ] Share install invite / release link with testers

## Install links (maintainers)

| Item | URL |
|------|-----|
| Actions | https://github.com/tmai-tech/RoomCraft/actions |
| Firebase App Distribution | https://console.firebase.google.com/project/roomcraft-e1312/appdistribution |
| Repo | https://github.com/tmai-tech/RoomCraft/tree/dev |

## Smoke test (10 minutes)

1. Fresh install → onboarding completes  
2. Settings → set Gemini key (if testing scan)  
3. Scan 1–2 photos → review → calibrate → open editor  
4. Or: draw walls + add furniture from catalog  
5. Auto-arrange bedroom → score updates  
6. Export PNG → share sheet opens  
7. Save → home shows thumbnail  
8. Duplicate plan → delete copy  
9. Home → Gallery → open **L-shape living** → 2D floor shows cutout  
10. Room size → **L-shape** → walkway heatmap toggle  
11. AR Room Planner (ARCore device) → measure → place layout → 3D  
12. Export PDF lists shape + furniture  
13. Home menu → **Duplicate as upper floor** → Floor 1 badge  
14. Gallery → **Backyard patio** → green exterior floor in 2D/3D  


## Play closed track (free path remaining)

- [x] Signed debug APK + Firebase App Distribution  
- [x] Stable CI keystore SHA  
- [ ] Store listing assets (feature graphic, screenshots 2D/3D/AR)  
- [ ] Privacy policy URL + data safety form  
- [x] In-app Privacy & data safety screen (+100)
- [ ] Closed testing track upload (Play Console)  
- [ ] 12+ testers for 14 days (when targeting open testing)  

## Metrics to watch

| Signal | Target (first 2 weeks) |
|--------|-------------------------|
| Installs via App Distribution | ≥ 10 |
| Completed scan→editor | ≥ 5 |
| Auto-arrange used | ≥ 5 |
| Export used | ≥ 3 |
| Crash-free sessions | No P0 on open/save/export |

## Feedback questions for testers

1. Did the top-down plan match your room roughly?  
2. Was scale calibration clear?  
3. Did auto-arrange help or fight you?  
4. What one feature is missing for you to use this weekly?  

## Release notes template (Firebase)

```
RoomCraft 1.0.0-beta.1
• Scan room photos → top-down blueprint
• Arrange furniture + auto-arrange
• Layout score & tips
• Export PNG
Known limits: AI scale is approximate — use calibration.
Feedback: Settings → Send feedback
```
