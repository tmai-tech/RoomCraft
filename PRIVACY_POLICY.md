# Privacy Policy for RoomCraft

**Last updated: July 18, 2026**

LogicRequire ("we", "us", or "our") operates the RoomCraft mobile application (the "App"). This page informs you of our policies regarding the collection, use, and disclosure of personal data when you use our App.

## 1. Information Collection and Use

### Camera Data
Our App requires access to your device's camera. This access is strictly used for:
- Scanning physical rooms to generate architectural blueprints.
- Analyzing room dimensions and furniture placement via AI.
Photos and AR camera frames are processed for:
- Optional photo scan / free vision furniture assist
- ARCore room measure and live furniture placement (frames stay on-device for AR)

Photos captured for optional free vision may be sent to Groq and/or Google Gemini. **We do not store your photos on our own servers.** AR placement uses on-device ARCore tracking.

### Local Storage
The App stores your room blueprints, app settings, and optional API keys locally on your device using `SharedPreferences`. This data remains on your device and is not collected by us. Free accurate scan works without any user-provided API key.

### AI Processing (optional free vision)
- **Offline accurate plan** (default): room size and walls are computed on-device from your measurements; photos are not uploaded.
- **Free vision furniture assist** (optional): room photos may be sent to Groq and/or Google Gemini to detect furniture. By using that mode, you agree to those providers' privacy policies.

## 2. Permissions
To provide its core functionality, the App requests the following permissions:
- **CAMERA**: To take photos of rooms for blueprint generation.
- **INTERNET**: To communicate with the Google Gemini API for AI analysis.
- **STORAGE**: To save and load your blueprints on your device.

## 3. Data Security
The security of your data is important to us, but remember that no method of transmission over the Internet or method of electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your personal data, we cannot guarantee its absolute security.

## 4. Third-Party Services
We may use third-party Service Providers to facilitate our App, including:
- Google AI / Gemini (optional free vision)
- Groq (optional free vision)
- Google Firebase (optional analytics, auth, cloud backup, App Distribution beta installs)
- Google ARCore (on-device AR)

These third parties may process data under their own policies when you use those features. These third parties have access to your Personal Data only to perform these tasks on our behalf and are obligated not to disclose or use it for any other purpose.

## 5. Contact Us
If you have any questions about this Privacy Policy, please contact us at:
prjoshi0711@gmail.com
