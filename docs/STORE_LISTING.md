# Play Store listing checklist (RoomCraft free path)

Use with [PLAY_AND_SIGNING.md](PLAY_AND_SIGNING.md) and [BETA_CHECKLIST.md](BETA_CHECKLIST.md).

## Assets (create offline / design tools)

| Asset | Spec | Content ideas |
|-------|------|----------------|
| App icon | 512×512 | Existing launcher icon |
| Feature graphic | 1024×500 | “Scan · Arrange · 3D · AR” |
| Phone screenshots (min 2) | 16:9 or device | Home, 2D editor + heatmap, 3D day/evening, AR place, gallery L-shape |
| Short description | ≤80 chars | Room planner: photo/AR → plan → 3D walkthrough |
| Full description | bullets | 10k free catalogue, AI furnish, L-shape, multi-floor, exterior patio |

## Data safety form (align with in-app screen)

- **Location:** not collected  
- **Photos:** collected only if user runs free vision assist or attaches feedback  
- **App activity:** optional analytics events  
- **App info & performance:** crash/diagnostics if Firebase enabled  
- **Data encrypted in transit:** yes (HTTPS to third parties)  
- **Users can request deletion:** delete app / clear data; cloud backup via account delete when enabled  

## Privacy policy URL

`AppConfig.privacyPolicyUrl` → `PRIVACY_POLICY.md` on `dev`.

## Closed testing

1. Internal/closed track AAB or APK  
2. ≥12 testers · 14 days before open testing (Google policy)  
3. Firebase App Distribution remains parallel beta channel  
