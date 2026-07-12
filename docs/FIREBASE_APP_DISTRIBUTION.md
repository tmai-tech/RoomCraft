# Firebase App Distribution — RoomCraft

## Current project status

| Item | Value |
|------|--------|
| Firebase project | `roomcraft-e1312` |
| Android package | `com.logicrequire.room_craft` |
| App ID | `1:768748224321:android:2ef77f7bc86ecb080fabc0` |
| Service account | `firebase-adminsdk-fbsvc@roomcraft-e1312.iam.gserviceaccount.com` |
| GitHub secrets | `FIREBASE_ANDROID_APP_ID`, `FIREBASE_SERVICE_ACCOUNT` set on `tmai-tech/RoomCraft` |
| Optional free vision | `ROOMCRAFT_GROQ_API_KEY` (and/or `ROOMCRAFT_GEMINI_API_KEY`) — bundled into APK so testers never paste keys |

## Required: one permission grant (you must do this once)

The Admin SDK service account **cannot** upload to App Distribution until a project Owner grants it a role.

### Grant role (2 minutes)

1. Open IAM:  
   https://console.cloud.google.com/iam-admin/iam?project=roomcraft-e1312

2. Find:  
   `firebase-adminsdk-fbsvc@roomcraft-e1312.iam.gserviceaccount.com`  
   (or click **Grant access** and paste that email)

3. Add role: **Firebase App Distribution Admin**  
   (`roles/firebaseappdistro.admin`)

4. Save

### Enable the API (if not already)

https://console.cloud.google.com/apis/library/firebaseappdistribution.googleapis.com?project=roomcraft-e1312  
→ **Enable**

### Create tester group (optional but recommended)

1. https://console.firebase.google.com/project/roomcraft-e1312/appdistribution  
2. **Testers & Groups** → group name **`testers`** → add emails  
3. Then set secret:

```bash
gh secret set FIREBASE_TESTER_GROUPS --repo tmai-tech/RoomCraft --body 'testers'
```

### Re-run distribution

```bash
gh workflow run "Build APK" --repo tmai-tech/RoomCraft --ref dev
```

Or push any commit to `dev`.

## How testers install

1. Invite email from Firebase App Distribution  
2. Open link on Android → install **Firebase App Tester** if prompted  
3. Download RoomCraft build

## CI behavior

After secrets + IAM are set, every successful **Build APK** run on `dev` / `main` / `master` uploads the debug APK to App Distribution.
