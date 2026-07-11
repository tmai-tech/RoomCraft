# Closed beta checklist — RoomCraft

## Before inviting testers

- [x] MVP phases 0–4 on `dev`
- [x] Version `1.0.0-beta.1+2`
- [x] Firebase App Distribution wired
- [x] Tester group `testers` exists
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
