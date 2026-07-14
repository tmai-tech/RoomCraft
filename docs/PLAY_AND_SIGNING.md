# Play signing, SHA fingerprints & Google Sign-In

Last updated: 2026-07-14 · Package `com.logicrequire.room_craft` · Firebase `roomcraft-e1312`

## Why this matters

Google Sign-In + Firebase Auth **require** the signing certificate **SHA-1** (and preferably SHA-256) registered on the Android app in Firebase.  
`google-services.json` currently has **empty `oauth_client`** until those fingerprints exist and you re-download the file.

Firebase App Distribution debug APKs must use a **stable keystore** — otherwise each CI runner has a new debug SHA and Sign-In keeps breaking.

## Fingerprints (RoomCraft)

| Cert | Use | SHA-1 | Status |
|------|-----|--------|--------|
| **CI / upload keystore** | All Firebase App Distribution APKs (after +12) | `B7:EF:A7:F5:C3:E6:E7:5E:9A:21:EF:4C:5C:F0:62:2F:11:A2:4B:09` | **Registered** 2026-07-14 via Management API |
| **Local Android debug** (this machine) | `flutter run` on a dev machine | `F3:8D:E3:8E:3A:FD:DD:BD:7D:84:9A:69:A2:06:09:14:A1:B1:A1:EF` | **Registered** 2026-07-14 |

CI SHA-256 (also registered):  
`B5:A3:58:DC:2A:BD:6F:98:03:18:66:F6:B9:17:4C:C9:6E:FD:93:36:8C:B8:C6:6C:CA:C0:6D:1B:E9:BD:64:2A`

Local debug SHA-256 (also registered):  
`FE:F6:6F:47:6B:93:23:E4:00:E4:36:9E:21:2E:7A:BD:1F:5A:BD:E6:F4:CB:35:A5:48:17:5E:FC:CB:E3:78:88`

Verify in Console: [Project settings → Android app](https://console.firebase.google.com/project/roomcraft-e1312/settings/general) should list both fingerprints.

### Infra applied programmatically (2026-07-14)

| Item | Status |
|------|--------|
| SHA-1 / SHA-256 on Android app | Done (4 certs) |
| Firestore `(default)` DB (`nam5`) | Created |
| Firestore security rules (`users/{uid}/rooms/*`) | Deployed |
| Web app (Auth helper) | Created |
| Firebase **Authentication** product | **Not started** — needs Owner click (see below) |
| `google-services.json` `oauth_client` | Still empty until Auth Google provider is enabled |
### Recompute fingerprints

```bash
# CI / upload keystore (local copy in .secrets — gitignored)
keytool -list -v -alias roomcraft \
  -keystore .secrets/roomcraft-ci.keystore \
  -storepass "$ANDROID_KEYSTORE_PASSWORD"

# Default Android debug keystore
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android -keypass android
```

## Console steps remaining (you — ~3 minutes)

SHAs, Firestore DB, and rules are already done. **One Owner-only step remains:** Firebase Auth was never initialized on this project (`CONFIGURATION_NOT_FOUND` / `firebase-core: disabled`). That cannot be finished with a service account alone.

### 1. Start Authentication + enable Google

1. Open [Authentication](https://console.firebase.google.com/project/roomcraft-e1312/authentication)
2. Click **Get started** (first-time only)
3. **Sign-in method** → **Google** → Enable → support email → Save

This creates the Web + Android OAuth clients and fills `oauth_client` in `google-services.json`.

### 2. Refresh `google-services.json` + web client secret

```bash
# From repo root (uses service account if GOOGLE_APPLICATION_CREDENTIALS is set)
./scripts/refresh-google-services.sh
# or:
export GOOGLE_APPLICATION_CREDENTIALS=.secrets/roomcraft-e1312-firebase-adminsdk-*.json
npx firebase-tools apps:sdkconfig ANDROID 1:768748224321:android:2ef77f7bc86ecb080fabc0 \
  --project roomcraft-e1312 --out android/app/google-services.json
```

Confirm `oauth_client` is **no longer empty**. Then set:

```bash
# client_type 3 entry from the new JSON
gh secret set ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID --repo tmai-tech/RoomCraft \
  --body 'XXXX.apps.googleusercontent.com'
```

CI already passes this as `--dart-define=ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID=...`.

Commit the updated JSON and re-run **Build APK**.

### 3. Firestore

Already created (`nam5`) with rules deployed. Re-deploy if you edit rules:

```bash
firebase deploy --only firestore:rules --project roomcraft-e1312
```

### 4. Verify on device

1. Install latest App Distribution build (after JSON + secret + rebuild)
2. Settings → **Sign in with Google**
3. Backup / restore a plan

If Sign-In fails, the snackbar message names the missing piece (SHA vs idToken vs Auth).
## GitHub secrets (signing)

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | Base64 of `.secrets/roomcraft-ci.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `roomcraft` |
| `ANDROID_KEY_PASSWORD` | Key password (same as store for PKCS12) |
| `ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID` | Web client ID (after step 4) |
| `FIREBASE_*` | App Distribution (already set) |

Local (gitignored): `android/key.properties` + `.secrets/roomcraft-ci.keystore`.

## Play Console closed testing (Phase 1.10)

Debug Firebase APKs are fine for closed beta. For **Play closed testing**:

1. Create app in [Play Console](https://play.google.com/console) — package `com.logicrequire.room_craft`
2. Prefer **Play App Signing** (Google holds the app signing key; you upload with upload keystore = CI keystore)
3. Create **Closed testing** track → add testers email list
4. Build release:

```bash
# with android/key.properties present
flutter build appbundle --release \
  --dart-define=ROOMCRAFT_GROQ_API_KEY=... \
  --dart-define=ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID=...
```

5. Upload `build/app/outputs/bundle/release/app-release.aab`
6. Complete Data safety, content rating, privacy policy URL
7. Add **Play App Signing** SHA-1 from Play Console → App integrity into Firebase (same as step 1)

### Checklist

- [ ] CI SHA-1 in Firebase
- [ ] Local debug SHA-1 in Firebase (developers)
- [ ] Google provider enabled
- [ ] `google-services.json` refreshed with `oauth_client`
- [ ] `ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID` secret set
- [ ] Firestore created + rules deployed
- [ ] Sign-in verified on a tester device
- [ ] (Later) Play closed track + AAB + Play SHA in Firebase

## Known limits

- Without SHA + Google provider, Settings → Sign in fails (plans still work offline)
- Photoreal / AR not blocked by signing — only Auth/Maps-style APIs
