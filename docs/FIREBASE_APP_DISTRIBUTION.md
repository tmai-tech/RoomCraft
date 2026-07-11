# Firebase App Distribution — RoomCraft

Testers install builds from email/invite links (no Play Store required).
CI uploads the debug APK after every successful **Build APK** run on `dev` / `main` / `master`.

## One-time Firebase console setup

### 1. Create / open a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/)
2. Create a project (e.g. `roomcraft`) or use an existing one
3. Disable Google Analytics if you do not need it (optional)

### 2. Register the Android app

1. **Project settings → Your apps → Add app → Android**
2. **Android package name** (must match exactly):

   ```
   com.logicrequire.room_craft
   ```

3. App nickname: `RoomCraft`
4. Register the app
5. Download `google-services.json` (optional for pure distribution of debug APKs; required if you enable Firebase SDKs in the app)
6. Copy the **App ID** — looks like:

   ```
   1:123456789012:android:abcdef0123456789
   ```

   This is `FIREBASE_ANDROID_APP_ID`.

### 3. Enable App Distribution

1. In the left menu: **Release & Monitor → App Distribution**
2. Get started if prompted

### 4. Create a tester group

1. App Distribution → **Testers & Groups**
2. Create group: **`testers`** (name must match the workflow default)
3. Add tester emails (they receive an invite)

### 5. Create a CI service account

1. Open [Google Cloud Console](https://console.cloud.google.com/) for the **same** Firebase project
2. **IAM & Admin → Service Accounts → Create service account**
   - Name: `github-app-distribution`
   - Role: **Firebase App Distribution Admin**  
     (and **Firebase Viewer** if the console suggests it)
3. **Keys → Add key → JSON** → download the JSON file
4. Keep this file private (never commit it)

## GitHub secrets (required)

In [tmai-tech/RoomCraft secrets](https://github.com/tmai-tech/RoomCraft/settings/secrets/actions):

| Secret | Value |
|--------|--------|
| `FIREBASE_ANDROID_APP_ID` | `1:…:android:…` from Firebase app settings |
| `FIREBASE_SERVICE_ACCOUNT` | **Full contents** of the service account JSON file |
| `FIREBASE_TESTER_GROUPS` | Optional; default `testers` (comma-separated groups) |

### Set secrets via CLI (from a machine with the JSON file)

```bash
# From the directory that contains the downloaded key
gh secret set FIREBASE_ANDROID_APP_ID --repo tmai-tech/RoomCraft --body '1:YOUR:android:APPID'
gh secret set FIREBASE_SERVICE_ACCOUNT --repo tmai-tech/RoomCraft < path/to/service-account.json
gh secret set FIREBASE_TESTER_GROUPS --repo tmai-tech/RoomCraft --body 'testers'
```

## How testers install

1. They receive an email from Firebase App Distribution (or accept an invite link you send)
2. On Android: open the link → install **Firebase App Tester** if asked → download RoomCraft
3. May need to allow installs from unknown sources / App Tester

## Trigger a distribution

Automatic:

- Push to `dev`, `main`, or `master` (not pull requests)

Manual:

```bash
gh workflow run "Build APK" --repo tmai-tech/RoomCraft --ref dev
```

## Local upload (optional)

```bash
npm i -g firebase-tools
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
firebase appdistribution:distribute dist/roomcraft-debug-latest.apk \
  --app "$FIREBASE_ANDROID_APP_ID" \
  --groups testers \
  --release-notes "Local upload"
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Workflow skips distribute step | Secrets not set or empty |
| 403 / permission denied | Service account needs **Firebase App Distribution Admin** |
| App not found | Wrong `FIREBASE_ANDROID_APP_ID` or package name mismatch |
| Testers get no email | Add them under **Testers & Groups** and resend invite |
