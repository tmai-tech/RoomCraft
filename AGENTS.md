# RoomCraft agent notes

## Always distribute after completing work

After finishing a user request that changes the app (code, CI, product features):

1. Push to `fork` remote branch `dev` (if not already).
2. Trigger **Build APK** workflow on `tmai-tech/RoomCraft` ref `dev`.
3. Confirm Firebase App Distribution upload; if group invite fails, re-run local distribute with `--groups testers`.
4. Give the user: Actions URL, Firebase release console URL, tester share link.

Secrets required: `FIREBASE_ANDROID_APP_ID`, `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_TESTER_GROUPS=testers`.

Local SA (gitignored): `.secrets/*-firebase-adminsdk-*.json`
