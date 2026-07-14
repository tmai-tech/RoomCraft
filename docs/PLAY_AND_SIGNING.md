# Play signing, SHA fingerprints & Google Sign-In

Last updated: 2026-07-14 · Package `com.logicrequire.room_craft` · Firebase `roomcraft-e1312`

## Why this matters

Google Sign-In + Firebase Auth **require** the signing certificate **SHA-1** (and preferably SHA-256) registered on the Android app in Firebase.  
`google-services.json` currently has **empty `oauth_client`** until those fingerprints exist and you re-download the file.

Firebase App Distribution debug APKs must use a **stable keystore** — otherwise each CI runner has a new debug SHA and Sign-In keeps breaking.

## Fingerprints (RoomCraft)

| Cert | Use | SHA-1 |
|------|-----|--------|
| **CI / upload keystore** | All Firebase App Distribution APKs (after +12) | `B7:EF:A7:F5:C3:E6:E7:5E:9A:21:EF:4C:5C:F0:62:2F:11:A2:4B:09` |
| **Local Android debug** (this machine) | `flutter run` on a dev machine | `F3:8D:E3:8E:3A:FD:DD:BD:7D:84:9A:69:A2:06:09:14:A1:B1:A1:EF` |

CI SHA-256 (optional, add both):  
`B5:A3:58:DC:2A:BD:6F:98:03:18:66:F6:B9:17:4C:C9:6E:FD:93:36:8C:B8:C6:6C:CA:C0:6D:1B:E9:BD:64:2A`

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

## Console steps (you — ~10 minutes)

### 1. Add SHA fingerprints

1. Open [Firebase Project settings → Your apps](https://console.firebase.google.com/project/roomcraft-e1312/settings/general)
2. Select Android app `com.logicrequire.room_craft`
3. **Add fingerprint** — paste **both** SHA-1 values above (CI + any local debug you use)
4. Save

### 2. Enable Google Sign-In

1. [Authentication → Sign-in method](https://console.firebase.google.com/project/roomcraft-e1312/authentication/providers)
2. Enable **Google** → set support email → Save

### 3. Re-download `google-services.json`

1. Same Project settings → Your apps → Download `google-services.json`
2. Replace `android/app/google-services.json` (commit it — needed for CI)
3. Confirm `oauth_client` is **no longer empty**

### 4. Web client ID for `idToken`

Find the OAuth client with `"client_type": 3` (Web client) in the new JSON:

```json
"client_id": "XXXX.apps.googleusercontent.com"
```

Set GitHub secret (and local dart-define):

```bash
gh secret set ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID --repo tmai-tech/RoomCraft \
  --body 'XXXX.apps.googleusercontent.com'
```

CI already passes this as `--dart-define=ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID=...`.

### 5. Firestore

1. [Create Firestore database](https://console.firebase.google.com/project/roomcraft-e1312/firestore) (production mode is fine if you deploy rules)
2. Deploy rules from this repo:

```bash
firebase login
firebase use roomcraft-e1312
firebase deploy --only firestore:rules
```

Rules file: `firestore.rules` — users may only read/write `users/{uid}/rooms/{roomId}`.

### 6. Verify on device

1. Install latest App Distribution build
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
